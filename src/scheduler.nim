##
## Basic Concepts
##
##
import threadpool
import asyncdispatch
import asyncfutures
import times
import tables
import strutils
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
  FnKind* = enum
    fkAsync,
    fkThread

  FnBase* = ref object of RootObj ## Untyped Fn.

  Fn*[TArg] = ref object of FnBase ## Typed Fn.
  ## It wraps the function and its arg.
  ##
  ## Currently, Fn supports proc running asynchronously or in threads.
    case kind*: FnKind
    of fkAsync:
      when TArg is void:
        asyncFn: proc (): Future[void] {.nimcall.}
      else:
        asyncFn: proc (arg: TArg): Future[void] {.nimcall.}
        asyncArg: TArg
    of fkThread:
      when TArg is void:
        threadFn: proc () {.nimcall, gcsafe.}
      else:
        threadFn: proc (arg: TArg) {.nimcall, gcsafe.}
        threadArg: TArg

proc initThreadFn*(
  fn: proc() {.thread, nimcall.},
): Fn[void] =
  Fn[void](kind: fkThread, threadFn: fn)

proc initThreadFn*[TArg](
  fn: proc(arg: TArg) {.thread, nimcall.},
  arg: TArg,
): Fn[TArg] =
  Fn[TArg](kind: fkThread, threadFn: fn, threadArg: arg)

proc initAsyncFn*(
  fn: proc(): Future[void] {.nimcall.},
): Fn[void] =
  Fn[void](kind: fkAsync, asyncFn: fn)

proc initAsyncFn*[TArg](
  fn: proc(): Future[TArg] {.nimcall.},
  arg: TArg,
): Fn[TArg] =
  Fn[TArg](kind: fkAsync, asyncFn: fn, asyncArg: arg)

type
  Job* = ref object of RootObj ## Untyped Job.
    id: string # The unique identity of the job.
    description: string # The description of the job.
    beater: Beater # The schedule of the job.
    f: FnBase # The runner of the job.
    ignoreDue: bool # Whether to ignore due job executions.
    maxDue: Duration # The max duration the job is allowed to due.
    parallel: int # The maximum number of parallel running job executions.
    fireTime: Option[DateTime] # The next scheduled run time.

proc `beater=`(job: Job, beater: Beater) =
  job.beater = beater

type
  JobCanceled = object of Exception

  JobMaxInstancesReached = object of Exception

type
  Runner* = ref object of RootObj
    jobNums: Table[string, int]
    pendingFutures: seq[Future[void]]

proc initRunner*(): Runner =
  Runner(jobNums: initTable[string, int](), pendingFutures: @[])

proc shutdown*(runner: Runner) =
  for fut in runner.pendingFutures:
    fut.fail(newException(JobCanceled, "runner is shutting down."))
  runner.pendingFutures = @[]

template keepNums*(runner: Runner, job: Job, body: untyped) =
  if runner.jobNums[job.id] >= job.parallel:
    raise newException(
      JobMaxInstancesReached,
      "id:" & job.id & ", max=" & job.parallel.intToStr
    )
  body
  runner.jobNums[job.id] += 1

proc submit*(runner: Runner, job: Job) {.async.} =
  runner.keepNums(job):
    echo("hello")

#proc run*[TArg](runner: Fn[TArg]) =
  #when TArg is void:
    #createThread(runner.thread, runner.fn)
  #else:
    #createThread(runner.thread, runner.fn, runner.arg)

#proc run*[TArg](runner: AsyncFn[TArg]) {.async.} =
  #var fut = when TArg is void:
    #fut = runner.fn()
  #else:
    #fut = runner.fn(runner.arg)
  #runner.future = fut
  #yield fut

#proc running*[TArg](runner: ThreadFn[TArg]) =
  #runner.thread.running

#proc running*[TArg](runner: AsyncFn[TArg]) =
  #not (runner.future.finished or runner.future.failed)

type
  TaskBase* = ref object of RootObj ## Untyped Task.
    id: string # The unique identity of the task.
    description: string # The description of the task.
    beater: Beater # The schedule of the task.
    f: FnBase # The runner of the task.
    ignoreDue: bool # Whether to ignore due task executions.
    maxDue: Duration # The max duration the task is allowed to due.
    parallel: int # The maximum number of parallel running task executions.
    fireTime: Option[DateTime] # The next scheduled run time.

  ThreadedTask*[TArg] = ref object of TaskBase
    thread: Thread[TArg] # deprecated
    when TArg is void:
      fn: proc () {.nimcall, gcsafe.}
    else:
      fn: proc (arg: TArg) {.nimcall, gcsafe.}
      arg: TArg

  AsyncTask*[TArg] = ref object of TaskBase
    future: Future[void]
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

type
  Scheduler* = ref object of RootObj ## Scheduler acts as an event loop and schedules all the tasks.

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
    await sleepAsync(1000)
    prev = now()

#let sched = AsyncScheduler()
#asyncCheck sched.start()
#runForever()
