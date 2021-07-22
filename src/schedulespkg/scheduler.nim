## # nim-schedules
##
## A Nim scheduler library that lets you kick off jobs at regular intervals.
##
## Example usage::
##
##     schedules:
##       every(seconds=1, id="tick", throttle=1, async=true):
##         echo("async tick ", now())
##         await sleepAsync(2000)
##       every(seconds=1, id="tick", throttle=1):
##         echo("sync tick ", now())
##

import macros, macrocache, options, times, asyncdispatch, tables, sequtils, logging

from ./cron/cron import Cron, newCron, getNext

var logger* = newConsoleLogger() ## By default, the logger is attached to no handlers.
## If you want to show logs, please call `addHandler(logger)`.

type
  BeaterAsyncProc* = proc (): Future[void] {.gcsafe, closure.}
  ## Async proc to be scheduled.

  BeaterThreadProc* = proc (): void {.gcsafe, thread.}
  ## Thread proc to be scheduled.
  ## It should be marked with pragma `{.thread.}`.
  ## It will be turned to BeaterAsyncProc in nim-schedules internally.

proc toAsync(p: BeaterThreadProc): BeaterAsyncProc =
  result =
    proc (): Future[void] {.gcsafe, closure, async.} =
      var thread: Thread[void]
      createThread(thread, p)
      while thread.running:
        await sleepAsync(1000)

type
  Throttler* = ref object ## Throttle the total number of beats.
    num: int
    beats: seq[Future[void]]

proc initThrottler*(num: int = 1): Throttler =
  ## Initialize the total number of beats allowed to be scheduled.
  ## By default, it's 1.
  ## If it's greater than 1, then more than one beats can be scheduled simultaneously.
  var beats: seq[Future[void]] = @[]
  Throttler(num: num, beats: beats)

proc throttled*(self: Throttler): bool =
  ## Whether the throttler is allowed to schedule more beats.
  self.beats.keepItIf(not it.finished)
  result = self.beats.len >= self.num

proc submit*(self: Throttler, fut: Future[void]) =
  ## Submit a new future to the throttler.
  ## WARNING: this function does not perform throttling check.
  self.beats.add(fut)

type
  BeaterKind* {.pure.} = enum
    bkInterval
    bkCron

  Beater* = ref object of RootObj ## Beater generates beats for the next runs.
    id: string
    startTime: DateTime
    endTime: Option[DateTime]
    beaterProc: BeaterAsyncProc
    throttler: Throttler
    case kind*: BeaterKind
    of bkInterval:
      interval*: TimeInterval
    of bkCron:
      cron*: Cron

proc `$`*(beater: Beater): string =
  case beater.kind
  of bkInterval:
    "Beater(" & $beater.kind & "," & $beater.interval & ")"
  of bkCron:
    "Beater(" & $beater.kind & "* * * * *" & ")"

proc initBeater*(
  interval: TimeInterval,
  asyncProc: BeaterAsyncProc,
  startTime: Option[DateTime] = none(DateTime),
  endTime: Option[DateTime] = none(DateTime),
  id: string = "",
  throttleNum: int = 1,
): Beater =
  ## Initialize a Beater, which kind is bkInterval.
  ##
  ## startTime and endTime are optional.
  Beater(
    id: id,
    kind: bkInterval,
    interval: interval,
    beaterProc: asyncProc,
    throttler: initThrottler(num=throttleNum),
    startTime: if startTime.isSome: startTime.get() else: now(),
    endTime: endTime,
  )

proc initBeater*(
  interval: TimeInterval,
  threadProc: BeaterThreadProc,
  startTime: Option[DateTime] = none(DateTime),
  endTime: Option[DateTime] = none(DateTime),
  id: string = "",
  throttleNum: int = 1,
): Beater =
  ## Initialize a Beater, which kind is bkInterval.
  ##
  ## startTime and endTime are optional.
  Beater(
    id: id,
    kind: bkInterval,
    interval: interval,
    beaterProc: threadProc.toAsync,
    throttler: initThrottler(num=throttleNum),
    startTime: if startTime.isSome: startTime.get() else: now(),
    endTime: endTime,
  )

proc initBeater*(
  cron: Cron,
  threadProc: BeaterThreadProc,
  startTime: Option[DateTime] = none(DateTime),
  endTime: Option[DateTime] = none(DateTime),
  id: string = "",
  throttleNum: int = 1,
): Beater =
  ## Initialize a Beater, which kind is bkInterval.
  ##
  ## startTime and endTime are optional.
  Beater(
    id: id,
    kind: bkCron,
    cron: cron,
    beaterProc: threadProc.toAsync,
    throttler: initThrottler(num=throttleNum),
    startTime: if startTime.isSome: startTime.get() else: now(),
    endTime: endTime,
  )

proc initBeater*(
  cron: Cron,
  asyncProc: BeaterAsyncProc,
  startTime: Option[DateTime] = none(DateTime),
  endTime: Option[DateTime] = none(DateTime),
  id: string = "",
  throttleNum: int = 1,
): Beater =
  ## Initialize a Beater, which kind is bkInterval.
  ##
  ## startTime and endTime are optional.
  Beater(
    id: id,
    kind: bkCron,
    cron: cron,
    beaterProc: asyncProc,
    throttler: initThrottler(num=throttleNum),
    startTime: if startTime.isSome: startTime.get() else: now(),
    endTime: endTime,
  )

proc fireTime*(
  self: Beater,
  prev: Option[DateTime],
  now: DateTime
): Option[DateTime] =
  ## Returns the next fire time of a task execution.
  ##
  ## For bkInterval, it has below rules:
  ##
  ## * For the 1st run,
  ##   * Choose `startTime` if it hasn't come.
  ##   * Choose the next `startTime + N * interval` that hasn't come.
  ## * For the rest of runs,
  ##   * Choose `prev + interval`.
  ##
  ## If `self.endTime` is set and greater than the fire time,
  ## a `none(DateTime)` is returned.
  result = case self.kind
  of bkInterval:
    some(
      if prev.isNone:
        if self.startTime >= now:
          self.startTime
        else:
          let passed = cast[int](now.toTime.toUnix - self.startTime.toTime.toUnix)
          let intervalLen = cast[int]((0.fromUnix + self.interval).toUnix)
          let leftSec = intervalLen - passed mod intervalLen
          now + initTimeInterval(seconds=leftSec)
      else:
        prev.get() + self.interval
    )
  of bkCron:
    self.cron.getNext(now)

  if self.endTime.isSome and result.get() > self.endTime.get():
    result = none(DateTime)

proc fire*(
  self: Beater
) {.async.} =
  ## Fire beats as async loop until no beats can be scheduled.
  var prev = none(DateTime)
  var nextRunTime = none(DateTime)
  while true:
    nextRunTime = self.fireTime(prev, now())
    if nextRunTime.isNone: break
    prev = nextRunTime

    let sleepDuration = nextRuntime.get() - now()
    let sleepMs = cast[int](sleepDuration.inMilliseconds)
    if sleepMs > 0:
      await sleepAsync(sleepMs)

    if not self.throttler.throttled:
      let fut = self.beaterProc()
      self.throttler.submit(fut)
      asyncCheck fut
    else:
      debug("\"", self.id, "\" is trottled. Maximum num is ", self.throttler.num, ".")


type
  Settings* = ref object
    appName*: string
    errorHandler*: proc (fut: Future[void]) {.closure, gcsafe.}

proc newSettings*(
  appName = "",
  errorHandler: proc (fut: Future[void]) {.closure, gcsafe.} = nil
): Settings =
  result = Settings(
    appName: appName,
    errorHandler: errorHandler
  )

type
  Scheduler* = ref object
    settings: Settings
    beaters: seq[Beater]
    futures: seq[Future[void]]

proc initScheduler*(settings: Settings): Scheduler =
  ## Initialize a scheduler.
  var beaters: seq[Beater] = @[]
  var futures: seq[Future[void]] = @[]
  result = Scheduler(
    settings: settings,
    beaters: beaters,
    futures: futures,
  )

proc register*(self: Scheduler, beater: Beater) =
  ## Register a beater.
  self.beaters.add(beater)

proc idle*(self: Scheduler) {.async.} =
  ## Idle the scheduler. It prevents the scheduler from shutdown when no beats is running.
  while true:
    await sleepAsync(1000)

proc start*(self: Scheduler) {.async.} =
  ## Start the scheduler.
  for beater in self.beaters:
    let fut = fire(beater)
    self.futures.add(fut)
    asyncCheck fut

proc serve*(self: Scheduler) =
  ## Serve the scheduler. It's a blocking function.
  asyncCheck idle(self)
  asyncCheck start(self)
  runForever()

proc waitFor*(self: Scheduler) =
  ## Run all beats til they're completed.
  waitFor start(self)

proc parseCron(call: NimNode): tuple[
  async: bool,
  id: NimNode,
  throttleNum: NimNode,
  body: NimNode,
  startTime: NimNode,
  endTime: NimNode,
  year: NimNode,
  month: NimNode,
  day_of_month: NimNode,
  day_of_week: NimNode,
  hour: NimNode,
  minute: NimNode,
] =
  var async: bool = false
  var id = newLit("")
  var throttleNum = newLit(1)
  var startTime = newCall(bindSym("none"), ident("DateTime"))
  var endTime = newCall(bindSym("none"), ident("DateTime"))
  var year, month, day_of_week, day_of_month, hour, minute  = newLit("*")
  let body = call[call.len-1]
  body.expectKind nnkStmtList
  for e in call[1 ..< call.len-1]:
    e.expectKind nnkExprEqExpr
    case e[0].`$`
    of "async": async = e[1].`$` == "true"
    of "id": id = e[1]
    of "throttle": throttleNum = e[1]
    of "startTime": startTime = newCall(bindSym("some"), e[1])
    of "endTime": endTime = newCall(bindSym("some"), e[1])
    of "year": year = e[1]
    of "month": month = e[1]
    of "day_of_month": day_of_month = e[1]
    of "day_of_week": day_of_week = e[1]
    of "hour": hour = e[1]
    of "minute": minute = e[1]
    else: macros.error("unexpected parameter for `cron`: " & e[0].`$`, call)
  result = (
    async: async,
    id: id,
    throttleNum: throttleNum,
    body: body,
    startTime: startTime,
    endTime: endTime,
    year: year,
    month: month,
    day_of_month: day_of_month,
    day_of_week: day_of_week,
    hour: hour,
    minute: minute,
  )

proc processCron(call: NimNode): NimNode=
  let (asyncProc, id, throttleNum, procBody, startTime, endTime, year, month, day_of_month, day_of_week, hour, minute) = parseCron(call)
  let cron = quote do:
    newCron(year=`year`, month=`month`, day_of_month=`day_of_month`, day_of_week=`day_of_week`, hour=`hour`, minute=`minute`)
  if asyncProc:
    result = quote do:
      initBeater(
        id = `id`,
        cron = `cron`,
        throttleNum = `throttleNum`,
        startTime = `startTime`,
        endTime = `endTime`,
        asyncProc = proc() {.async.} =
          `procBody`
      )
  else:
    result = quote do:
      initBeater(
        id = `id`,
        cron = `cron`,
        throttleNum = `throttleNum`,
        startTime = `startTime`,
        endTime = `endTime`,
        threadProc = proc() {.thread.} =
          `procBody`
      )

proc parseEvery(call: NimNode): tuple[
  async: bool,
  id: NimNode,
  throttleNum: NimNode,
  body: NimNode,
  milliseconds: NimNode,
  seconds: NimNode,
  minutes: NimNode,
  hours: NimNode,
  days: NimNode,
  weeks: NimNode,
  months: NimNode,
  years: NimNode,
  startTime: NimNode,
  endTime: NimNode,
] =
  var async: bool = false
  var id = newLit("")
  var throttleNum = newLit(1)
  var startTime = newCall(bindSym("none"), ident("DateTime"))
  var endTime = newCall(bindSym("none"), ident("DateTime"))
  var years, months, weeks, days, hours, minutes, seconds, milliseconds = newLit(0)
  let body = call[call.len-1]
  body.expectKind nnkStmtList
  for e in call[1 ..< call.len-1]:
    e.expectKind nnkExprEqExpr
    case e[0].`$`
    of "async": async = e[1].`$` == "true"
    of "id": id = e[1]
    of "throttle": throttleNum = e[1]
    of "years": years = e[1]
    of "months": months = e[1]
    of "weeks": weeks = e[1]
    of "days": days = e[1]
    of "hours": hours = e[1]
    of "minutes": minutes = e[1]
    of "seconds": seconds = e[1]
    of "milliseconds": milliseconds = e[1]
    of "startTime": startTime = newCall(bindSym("some"), e[1])
    of "endTime": endTime = newCall(bindSym("some"), e[1])
    else: macros.error("unexpected parameter for `every`: " & e[0].`$`, call)
  result = (
    async: async,
    id: id,
    throttleNum: throttleNum,
    body: body,
    milliseconds: milliseconds,
    seconds: seconds,
    minutes: minutes,
    hours: hours,
    days: days,
    weeks: weeks,
    months: months,
    years: years,
    startTime: startTime,
    endTime: endTime,
  )

proc processEvery(call: NimNode): NimNode=
  let (asyncProc, id, throttleNum, procBody, milliseconds, seconds,
    minutes, hours, days, weeks, months, years, startTime, endTime) = parseEvery(call)
  let interval = quote do:
    initTimeInterval(
      years=`years`, months=`months`, weeks=`weeks`, days=`days`, hours=`hours`,
      minutes=`minutes`, seconds=`seconds`, milliseconds=`milliseconds`,
    )
  if asyncProc:
    result = quote do:
      initBeater(
        id = `id`,
        interval = `interval`,
        throttleNum = `throttleNum`,
        startTime = `startTime`,
        endTime = `endTime`,
        asyncProc = proc() {.async.} =
          `procBody`
      )
  else:
    result = quote do:
      initBeater(
        id = `id`,
        interval = `interval`,
        throttleNum = `throttleNum`,
        startTime = `startTime`,
        endTime = `endTime`,
        threadProc = proc() {.thread.} =
          `procBody`
      )

proc processSchedule(call: NimNode): NimNode =
  call.expectKind nnkCall
  let cmdName = call[0].`$`
  case cmdName
  of "every": processEvery(call)
  of "cron": processCron(call)
  else: raise newException(Exception, "unknown cmd: " & cmdName)

proc schedulerEx(sched: NimNode, body: NimNode): NimNode =
  if sched.kind != nnkIdent: macros.error(
    "Need an indent after macro `router`.", sched
  )

  body.expectKind nnkStmtList

  result = newStmtList()
  result.add(quote do:
    var `sched` = initScheduler(newSettings())
  )
  for call in body:
    let beaterNode = processSchedule(call)
    result.add(quote do:
      `sched`.register(`beaterNode`)
    )

macro scheduler*(sched: untyped, body: untyped): typed =
  ## Initialize a scheduler and register code blocks as beats.
  ##
  ## You'll use it when you want to mix using nim-schedules
  ## with some other libraries, such as jester, etc.
  result = schedulerEx(sched, body)

macro schedules*(body: untyped): untyped =
  ## Initialize a scheduler, register code blocks as beats,
  ## and run it as a blocking application.
  ##
  ## You'll use it when the scheduled jobs are the only thing
  ## your programm will need to handle.
  let ident = newIdentNode("scheduler")
  result = schedulerEx(ident, body)
  result.add(quote do:
    `ident`.serve()
  )
