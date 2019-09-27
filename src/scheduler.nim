## 
## Basic Concepts
##
##
import threadpool
import asyncdispatch
import asyncfutures
import times

type
  Beater* = ref object of RootObj ## Beater generates beats for the next runs.

method nextTime*(self: Beater, asOf: DateTime, prev: DateTime): DateTime {.base.} =
  0.fromUnix.utc

type
  CronBeater* = ref object of Beater

type
  IntervalBeater* = ref object of Beater
    interval*: TimeInterval

method nextTime*(self: IntervalBeater, asOf: DateTime, prev: DateTime): DateTime =
  prev + self.interval

type
  ExecutorKind* = enum
    ekThread,
    ekProcess,
    ekAsync

  TaskBase* = ref object of RootObj
    id: string
    beater: Beater

  Task*[TArg] = ref object of TaskBase

  ThreadedTask*[TArg] = ref object of Task[TArg]
    thread: Thread[TArg]
    when TArg is void:
      fn: proc () {.nimcall, gcsafe.}
    else:
      fn: proc (arg: TArg) {.nimcall, gcsafe.}
      arg: TArg

  AsyncTask*[TArg] = ref object of Task[TArg]
    future: Future[void]
    when TArg is void:
      fn: proc (): Future[void] {.nimcall.}
    else:
      fn: proc (arg: TArg): Future[void] {.nimcall.}
      arg: TArg

proc newThreadedTask*(fn: proc() {.thread, nimcall.}, beater: Beater, id=""): ThreadedTask[void] =
  var thread: Thread[void]
  result = ThreadedTask[void](id: id, thread: thread, fn: fn, beater: beater)

proc newThreadedTask*[TArg](
  fn: proc(arg: TArg) {.thread, nimcall.},
  arg: TArg,
  beater: Beater,
  id=""
): ThreadedTask[TArg] =
  var thread: Thread[TArg]
  result = ThreadedTask[TArg](id: id, thread: thread, fn: fn, arg: arg, beater: beater)

proc newAsyncTask*(
  fn: proc(): Future[void] {.nimcall.},
  beater: Beater,
  id=""
): AsyncTask[void] =
  var future = newFuture[void](id)
  result = AsyncTask[void](id: id, future: future, fn: fn, beater: beater)

proc newAsyncTask*[TArg](
  fn: proc(arg: TArg): Future[void] {.nimcall.},
  arg: TArg,
  beater: Beater,
  id=""
): AsyncTask[TArg] =
  var future = newFuture[void](id)
  result = AsyncTask[TArg](id: id, future: future, fn: fn, arg: arg, beater: beater)

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
  Runner* = ref object of RootObj ## Runner runs the tasks.

type
  Storage* = ref object of RootObj ## Storage stores tasks definitions.

type
  Scheduler* = ref object of RootObj ## Scheduler acts as an event loop and schedules all the tasks.

type
  MemStorage* = ref object of Storage

type
  AsyncRunner* = ref object of Runner

type
  ThreadRunner* = ref object of Runner

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
  let beater = IntervalBeater(interval: TimeInterval(seconds: 1))
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

let sched = AsyncScheduler()
asyncCheck sched.start()
runForever()
