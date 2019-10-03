## # nim-schedules
##
## A Nim scheduler library that lets you kicks off jobs at regular intervals.
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

var logger* = newConsoleLogger() ## By default, the logger is attached to no handlers.
## If you want to show logs, please call `addHandler(logger)`.

type
  BeaterErrorKind* = enum
    BeaterInternalError

  BeaterError* = object ## Interval error. It's for nim-schedules internal use.
    case kind*: BeaterErrorKind
    of BeaterInternalError:
      exc: ref Exception

  ErrorProc* = proc (err: BeaterError): Future[void] {.gcsafe, closure.}
  ## TODO: enable setting error handler

proc initBeaterInternalError(exc: ref Exception): BeaterError =
  BeaterError(kind: BeaterInternalError, exc: exc)

type
  BeaterProcAsync* = proc (): Future[void] {.gcsafe, closure.}
  ## Async proc that is to schedule.

  BeaterProcSync* = proc (): void {.gcsafe, thread.}
  ## Sync proc that is to schedule.
  ## It should be marked with pragma `{.thread.}`.
  ## It will be turned to BeaterProcAsync in nim-schedules internally.

  BeaterProc = object
    asyncProc: BeaterProcAsync

proc toAsync(p: BeaterProcSync): BeaterProcAsync =
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
    #bkCron: TODO

  Beater* = ref object of RootObj ## Beater generates beats for the next runs.
    id: string
    startTime: DateTime
    endTime: Option[DateTime]
    beaterProc: BeaterProc
    throttler: Throttler
    case kind*: BeaterKind
    of bkInterval:
      interval*: TimeInterval

proc `$`*(beater: Beater): string =
  case beater.kind
  of bkInterval:
    "Beater(" & $beater.kind & "," & $beater.interval & ")"

proc initBeater*(
  interval: TimeInterval,
  asyncProc: BeaterProcAsync,
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
    beaterProc: BeaterProc(asyncProc: asyncProc),
    throttler: initThrottler(num=throttleNum),
    startTime: if startTime.isSome: startTime.get() else: now(),
    endTime: endTime,
  )

proc initBeater*(
  interval: TimeInterval,
  syncProc: BeaterProcSync,
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
    beaterProc: BeaterProc(asyncProc: syncProc.toAsync),
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
  result = some(
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

    if not self.throttler.throttled:
      let fut = self.beaterProc.asyncProc()
      self.throttler.submit(fut)
      asyncCheck fut
    else:
      debug("\"", self.id, "\" is trottled. Maximum num is ", self.throttler.num, ".")

    let sleepDuration = max(initDuration(seconds = 1), nextRunTime.get()-now())
    await sleepAsync(cast[int](sleepDuration.inMilliseconds))


type
  Settings* = ref object
    appName*: string
    errorHandler*: proc (fut: Future[void]) {.closure, gcsafe.}

proc newSettings(
  appName = "",
  errorHandler: proc (fut: Future[void]) {.closure, gcsafe.} = nil
): Settings =
  result = Settings(
    appName: appName,
    errorHandler: errorHandler
  )

template declareSettings(): void {.dirty.} =
  when not declaredInScope(settings):
    var settings = newSettings()


type
  Scheduler* = ref object
    settings: Settings
    beaters: seq[Beater]
    futures: seq[Future[void]]
    errHandlers: Table[BeaterErrorKind, ErrorProc]

proc initScheduler*(settings: Settings): Scheduler =
  ## Initialize a scheduler.
  var beaters: seq[Beater] = @[]
  var futures: seq[Future[void]] = @[]
  var errHandlers = initTable[BeaterErrorKind, ErrorProc]()
  result = Scheduler(
    settings: settings,
    beaters: beaters,
    futures: futures,
    errHandlers: errHandlers
  )

proc register*(self: Scheduler, beater: Beater) =
  ## Register a beater.
  self.beaters.add(beater)

proc register*(self: Scheduler, kind: BeaterErrorKind, errHandler: ErrorProc) =
  ## Register an error handler.
  ## (Not used as of now)
  self.errHandlers[kind] = errHandler

proc idle*(self: Scheduler) {.async.} =
  ## Idle the scheduler. It prevents the scheduler from shutdown when no beats is running.
  while true:
    await sleepAsync(1000)

proc handleError*(self: Scheduler, err: BeaterError) {.async.} =
  if self.errHandlers.contains(err.kind):
    let errHandler = self.errHandlers[err.kind]
    asyncCheck errHandler(err)

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
] =
  var async: bool = false
  var id = newLit(0)
  var throttleNum = newLit(1)
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
  )

proc processEvery(call: NimNode): NimNode=
  let (async, id, throttleNum, procBody, milliseconds, seconds,
    minutes, hours, days, weeks, months, years) = parseEvery(call)
  let interval = quote do:
    initTimeInterval(
      years=`years`, months=`months`, weeks=`weeks`, days=`days`, hours=`hours`,
      minutes=`minutes`, seconds=`seconds`, milliseconds=`milliseconds`,
    )
  if async:
    result = quote do:
      initBeater(
        id = `id`,
        interval = `interval`,
        throttleNum = `throttleNum`,
        asyncProc = proc() {.async.} =
          `procBody`
      )
  else:
    result = quote do:
      initBeater(
        id = `id`,
        interval = `interval`,
        throttleNum = `throttleNum`,
        syncProc = proc() {.thread.} =
          `procBody`
      )

proc processSchedule(call: NimNode): NimNode =
  call.expectKind nnkCall
  let cmdName = call[0].`$`
  case cmdName
  of "every": processEvery(call)
  else: raise newException(Exception, "unknown cmd: " & cmdName)

macro schedules*(body: untyped): untyped =
  ## Initialize a scheduler and register code blocks as beats.
  body.expectKind nnkStmtList
  let schedulerIdent = newIdentNode("scheduler")

  result = newStmtList()
  result.add(quote do:
    var `schedulerIdent` = initScheduler(newSettings())
  )
  for call in body:
    let beaterNode = processSchedule(call)
    result.add(quote do:
      `schedulerIdent`.register(`beaterNode`)
    )
  result.add(quote do:
    `schedulerIdent`.serve()
  )

