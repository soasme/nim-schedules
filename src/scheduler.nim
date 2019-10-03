import macros, macrocache, options, times, asyncdispatch, tables, sequtils, logging

var logger* = newConsoleLogger()

type
  BeaterErrorKind* = enum
    BeaterInternalError

  BeaterError* = object
    case kind*: BeaterErrorKind
    of BeaterInternalError:
      exc: ref Exception

  ErrorProc* = proc (err: BeaterError): Future[void] {.gcsafe, closure.}

proc initBeaterInternalError(exc: ref Exception): BeaterError =
  BeaterError(kind: BeaterInternalError, exc: exc)

type
  BeaterProcAsync* = proc (): Future[void] {.gcsafe, closure.}

  BeaterProcSync* = proc (): void {.gcsafe, thread.}

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
  Throttler* = ref object
    num: int
    beats: seq[Future[void]]

proc initThrottler(num: int = 1): Throttler =
  var beats: seq[Future[void]] = @[]
  Throttler(num: num, beats: beats)

proc throttled(self: Throttler): bool =
  self.beats.keepItIf(not it.finished)
  result = self.beats.len >= self.num

proc submit(self: Throttler, fut: Future[void]) =
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
  self.beaters.add(beater)

proc register*(self: Scheduler, kind: BeaterErrorKind, errHandler: ErrorProc) =
  self.errHandlers[kind] = errHandler

proc idle*(self: Scheduler) {.async.} =
  while true:
    await sleepAsync(1000)

proc handleError*(self: Scheduler, err: BeaterError) {.async.} =
  if self.errHandlers.contains(err.kind):
    let errHandler = self.errHandlers[err.kind]
    asyncCheck errHandler(err)

proc start*(self: Scheduler) {.async.} =
  for beater in self.beaters:
    let fut = fire(beater)
    self.futures.add(fut)
    asyncCheck fut

proc serve*(self: Scheduler) =
  asyncCheck idle(self)
  asyncCheck start(self)
  runForever()

proc waitFor*(self: Scheduler) =
  waitFor start(self)

proc parseEvery(call: NimNode): tuple[
  async: bool,
  id: string,
  throttleNum: int,
  body: NimNode,
  milliseconds: int,
  seconds: int,
  minutes: int,
  hours: int,
  days: int,
  weeks: int,
  months: int,
  years: int,
] =
  var async: bool = false
  var id: string = ""
  var throttleNum: int = 1
  var years, months, weeks, days, hours, minutes, seconds, milliseconds: int = 0
  for e in call[1 ..< call.len-1]:
    e.expectKind nnkExprEqExpr
    case e[0].`$`
    of "async":
      case e[1].`$`
      of "true": async = true
      else: async = false
    of "id":
      id = e[1].`$`
    of "throttle":
      throttleNum = cast[int](e[1].intVal)
    of "years":
      years = cast[int](e[1].intVal)
    of "months":
      months = cast[int](e[1].intVal)
    of "weeks":
      weeks = cast[int](e[1].intVal)
    of "days":
      days = cast[int](e[1].intVal)
    of "hours":
      hours = cast[int](e[1].intVal)
    of "minutes":
      minutes = cast[int](e[1].intVal)
    of "seconds":
      seconds = cast[int](e[1].intVal)
    of "milliseconds":
      milliseconds = cast[int](e[1].intVal)

  let body = call[call.len-1]
  body.expectKind nnkStmtList

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
  let res = parseEvery(call)
  let procBody = res.body
  let idNode = newLit(res.id)
  let throttleNumNode = newLit(res.throttleNum)
  # TODO: set interval
  if res.async:
    result = quote do:
      initBeater(
        id = `idNode`,
        interval = TimeInterval(seconds: 1),
        throttleNum = `throttleNumNode`,
        asyncProc = proc() {.async.} =
          `procBody`
      )
  else:
    result = quote do:
      initBeater(
        id = `idNode`,
        interval = TimeInterval(seconds: 1),
        throttleNum = `throttleNumNode`,
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

  body.expectKind nnkStmtList

  result = newStmtList()

  let schedulerIdent = newIdentNode("scheduler")

  # initialize a scheduler
  result.add(quote do:
    var `schedulerIdent` = initScheduler(newSettings())
  )

  # register beaters
  for call in body:
    let beaterNode = processSchedule(call)
    result.add(quote do:
      `schedulerIdent`.register(`beaterNode`)
    )

  # serve the scheduler
  result.add(quote do:
    `schedulerIdent`.serve()
  )

addHandler(logger)

schedules:

   every(seconds=1, id="tick", throttle=1, async=true):
     echo("async tick ", now())
     await sleepAsync(2000)

   every(seconds=1, id="tick", throttle=1):
     echo("sync tick ", now())

   # TODO
   #cron("*/1 * * * *", id="tick", throttle=2):
     #echo("tick", now())
     #await sleepAsync(1000)
