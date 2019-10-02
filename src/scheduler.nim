import macros, macrocache, options, times, asyncdispatch, tables

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
    case async: bool
    of true:
      asyncProc: BeaterProcAsync
    of false:
      syncProc: BeaterProcSync


type
  BeaterKind* {.pure.} = enum
    bkInterval
    bkCron

  Beater* = ref object of RootObj ## Beater generates beats for the next runs.
    startTime: DateTime
    endTime: Option[DateTime]
    beaterProc: BeaterProc
    case kind*: BeaterKind
    of bkInterval:
      interval*: TimeInterval
    of bkCron:
      expr*: string # TODO, parse `* * * * *`

proc `$`*(beater: Beater): string =
  case beater.kind
  of bkInterval:
    "Beater(" & $beater.kind & "," & $beater.interval & ")"
  of bkCron:
    "Beater(" & $beater.kind & "," & beater.expr & ")"

proc initBeater*(
  interval: TimeInterval,
  asyncProc: BeaterProcAsync,
  startTime: Option[DateTime] = none(DateTime),
  endTime: Option[DateTime] = none(DateTime),
): Beater =
  ## Initialize a Beater, which kind is bkInterval.
  ##
  ## startTime and endTime are optional.
  Beater(
    kind: bkInterval,
    interval: interval,
    beaterProc: BeaterProc(async: true, asyncProc: asyncProc),
    startTime: if startTime.isSome: startTime.get() else: now(),
    endTime: endTime,
  )

proc initBeater*(
  interval: TimeInterval,
  syncProc: BeaterProcSync,
  startTime: Option[DateTime] = none(DateTime),
  endTime: Option[DateTime] = none(DateTime),
): Beater =
  ## Initialize a Beater, which kind is bkInterval.
  ##
  ## startTime and endTime are optional.
  Beater(
    kind: bkInterval,
    interval: interval,
    beaterProc: BeaterProc(async: false, syncProc: syncProc),
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
  let prev = none(DateTime)
  var nextRunTime = none(DateTime)
  while true:
    nextRunTime = self.fireTime(prev, now())
    if nextRunTime.isNone: break

    case self.beaterProc.async
    of true:
      asyncCheck self.beaterProc.asyncProc()
    of false:
      var thread: Thread[void]
      createThread(thread, self.beaterProc.syncProc)

    let sleepDuration = max(initDuration(seconds = 1), nextRunTime.get()-now())
    await sleepAsync(cast[int](sleepDuration.inMilliseconds))


const SCHEDULED_JOBS = CacheTable"beater.jobs"

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

template declareSettings(): typed {.dirty.} =
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

  asyncCheck self.idle()

proc serve*(self: Scheduler) =
  asyncCheck start(self)
  runForever()

# TODO: DSL:
# schedules:
#
#   cron("touch a file", "*/1 * * * *"):
#     let code = execCmd("touch .touched")
#     echo(beater.id, ", exitCode=", code)
#
#   interval("tick", seconds=2):
#     echo("tick", now())
#     await sleepAsync(1000)
#     echo("tick", now())
#
proc scheduleEx(name: string, body: NimNode): NimNode =
  SCHEDULED_JOBS[name] = body.copyNimTree

  result = newStmtList()
  result.add(
    quote do:
      declareSettings()
  )

proc syncTick() {.thread.} = echo("sync tick", now())
proc asyncTick() {.async.} = echo("async tick", now())

let beater = initBeater(
  interval = TimeInterval(seconds: 2),
  asyncProc = asyncTick,
  endTime = some(now()+initDuration(seconds=5))
)
let scheduler = initScheduler(newSettings())
scheduler.register(beater)
scheduler.serve()
