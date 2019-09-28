##
## Basic Concepts
##
##
import threadpool
import asyncdispatch
import asyncfutures
import times
import options

type
  BeaterKind* {.pure.} = enum
    bkInterval
    bkCron

  Beater* = ref object of RootObj ## Beater generates beats for the next runs.
    startTime: DateTime
    endTime: Option[DateTime]
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
  startTime: Option[DateTime] = none(DateTime),
  endTime: Option[DateTime] = none(DateTime),
): Beater =
  ## Initialize a Beater, which kind is bkInterval.
  ##
  ## startTime and endTime are optional.
  Beater(
    kind: bkInterval,
    interval: interval,
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

type
  RunnerKind* = enum
    rkAsync,
    rkThread

  RunnerBase* = ref object of RootObj ## Untyped runner.

  AsyncRunner*[TArg] = ref object of RunnerBase ## Runs in an async loop.
    future: Future[void]
    when TArg is void:
      fn: proc (): Future[void] {.nimcall.}
    else:
      fn: proc (arg: TArg): Future[void] {.nimcall.}
      arg: TArg

  ThreadRunner*[TArg] = ref object of RunnerBase ## Runs in a thread.
    thread: Thread[TArg]
    when TArg is void:
      fn: proc () {.nimcall, gcsafe.}
    else:
      fn: proc (arg: TArg) {.nimcall, gcsafe.}
      arg: TArg

  AnyRunner* = AsyncRunner | ThreadRunner

proc kind*(runner: AnyRunner): RunnerKind = ## Returns the kind of any Runner type.
  when runner is AsyncRunner:
    rkAsync
  elif runner is ThreadRunner:
    rkThread

proc run*[TArg](runner: ThreadRunner[TArg]) =
  when TArg is void:
    createThread(runner.thread, runner.fn)
  else:
    createThread(runner.thread, runner.fn, runner.arg)

proc run*[TArg](runner: AsyncRunner[TArg]) {.async.} =
  var fut = when TArg is void:
    fut = runner.fn()
  else:
    fut = runner.fn(runner.arg)
  runner.future = fut
  yield fut

type
  TaskBase* = ref object of RootObj ## Untyped Task.
    id: string # The unique identity of the task.
    description: string # The description of the task.
    beater: Beater # The schedule of the task.
    ignoreDue: bool # Whether to ignore due task executions.
    maxDue: Duration # The max duration the task is allowed to due.
    parallel: int # The maximum number of parallel running task executions.
    fireTime: Option[DateTime] # The next scheduled run time.

  ThreadedTask*[TArg] = ref object of TaskBase
    thread: Thread[TArg] # deprecated
    threads: seq[Thread[TArg]]
    when TArg is void:
      fn: proc () {.nimcall, gcsafe.}
    else:
      fn: proc (arg: TArg) {.nimcall, gcsafe.}
      arg: TArg

  AsyncTask*[TArg] = ref object of TaskBase
    future: Future[void]
    futures: seq[Future[void]]
    when TArg is void:
      fn: proc (): Future[void] {.nimcall.}
    else:
      fn: proc (arg: TArg): Future[void] {.nimcall.}
      arg: TArg

proc newThreadedTask*(fn: proc() {.thread, nimcall.}, beater: Beater, id=""): ThreadedTask[void] =
  var thread: Thread[void]
  return ThreadedTask[void](
    id: id,
    thread: thread,
    fn: fn,
    beater: beater,
    fireTime: none(DateTime),
  )

proc newThreadedTask*[TArg](
  fn: proc(arg: TArg) {.thread, nimcall.},
  arg: TArg,
  beater: Beater,
  id=""
): ThreadedTask[TArg] =
  var thread: Thread[TArg]
  return ThreadedTask[TArg](
    id: id,
    thread: thread,
    fn: fn,
    arg: arg,
    beater: beater,
    fireTime: none(DateTime),
  )

proc newAsyncTask*(
  fn: proc(): Future[void] {.nimcall.},
  beater: Beater,
  id=""
): AsyncTask[void] =
  var future = newFuture[void](id)
  result = AsyncTask[void](
    id: id,
    future: future,
    fn: fn,
    beater: beater,
    fireTime: none(DateTime),
  )

proc newAsyncTask*[TArg](
  fn: proc(arg: TArg): Future[void] {.nimcall.},
  arg: TArg,
  beater: Beater,
  id=""
): AsyncTask[TArg] =
  var future = newFuture[void](id)
  result = AsyncTask[TArg](
    id: id,
    future: future,
    fn: fn,
    arg: arg,
    beater: beater,
    fireTime: none(DateTime),
  )

proc fire*(task: ThreadedTask[void]) =
  createThread(task.thread, task.fn)

proc fire*[TArg](task: ThreadedTask[TArg]) =
  createThread(task.thread, task.fn, task.arg)

proc fire*(task: AsyncTask[void]) {.async.} =
  var fut = task.fn()
  task.future = fut
  yield fut
  if fut.failed:
    echo("AsyncTask " & task.id & " fire failed.")

proc fire*[TArg](task: AsyncTask[TArg]) {.async.} =
  var fut = task.fn(task.arg)
  task.future = fut
  yield fut
  if fut.failed:
    echo("AsyncTask " & task.id & " fire failed.")

proc running*[TArg](task: ThreadedTask[TArg]) =
  task.thread.running

proc running*[TArg](task: AsyncTask[TArg]) =
  not (task.future.finished or task.future.failed)


type
  Storage* = ref object of RootObj ## Storage stores tasks definitions.

type
  Scheduler* = ref object of RootObj ## Scheduler acts as an event loop and schedules all the tasks.

type
  MemStorage* = ref object of Storage

type
  AsyncScheduler* = ref object of Scheduler

proc tick(since: DateTime) {.thread.} =
  echo(now() - since)

proc tick2() {.thread.} =
  echo(now())

proc atick() {.async.} =
  await sleepAsync(1000)
  echo("async tick")

proc start(self: AsyncScheduler) {.async.} =
  let beater = initBeater(interval=TimeInterval(seconds: 1))
  let task = newThreadedTask[DateTime](tick, now(), beater=beater)
  let atask = newAsyncTask(atick, beater=beater)
  #let task = newThreadedTask(tick2, beater)
  var prev = now()
  while true:
    asyncCheck atask.fire()
    task.fire()

    echo(task.thread.running)
    await sleepAsync(1000)
    echo(task.thread.running)
    prev = now()

#let sched = AsyncScheduler()
#asyncCheck sched.start()
#runForever()
