import threadpool
import asyncdispatch
import sugar
import times

type
  Task* = ref object
    id*: string
    f*: proc (): Future[void]

type
  Beater* = ref object of RootObj ## Beater generates beats for the next runs.

method nextTime*(self: Beater, asOf: DateTime, prev: DateTime): DateTime {.base.} =
  echo("NotImplementedError: newTick"); quit(1)

type
  CronBeater* = ref object of Beater

type
  IntervalBeater* = ref object of Beater
    interval*: TimeInterval
    start_time*: ref DateTime
    end_time*: ref DateTime

method nextTime*(self: IntervalBeater, asOf: DateTime, prev: DateTime): DateTime =
  prev + self.interval

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

type
  ScheduleError* = object of Exception

proc tick() {.async.} =
  echo("tick ", now())

proc start(self: AsyncScheduler) {.async.} =
  let beater = IntervalBeater(interval: TimeInterval(seconds: 1))
  let task = Task(id: "tick", f: tick)
  while true:
    let fut = task.f()
    #asyncCheck(fut)
    await sleepAsync(1000)

let sched = AsyncScheduler()
asyncCheck sched.start()
runForever()
