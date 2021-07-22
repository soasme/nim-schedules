## # nim-schedules
##
## A Nim scheduler library that lets you kick off jobs at regular intervals.
##
## ## Schedule By Every
##
## Example usage::
##
##     import schedules, times, asyncdispatch
##
##     schedules:
##       every(seconds=1, id="tick", async=true):
##         echo("async tick ", now())
##         await sleepAsync(2000)
##       every(seconds=1, id="tick"):
##         echo("sync tick ", now())
##
## The code enables you:
##
## * Schedule thread proc every 10 seconds.
## * Schedule async proc every 10 seconds.
##
## Run::
##
##     nim c --threads:on -r everyExample.nim
##
## Note:
##
## * Don't forget --threads:on when compiling your application.
## * The library schedules all jobs at a regular interval, but it'll be impacted by your system load.
##
## ## Schedule By Cron
##
## You can set minute, hour, day_of_month, month, day_of_week, and year in the cron() call.
## Each field is a string in cron-syntax, containing any of the allowed values, along with various combinations of the allowed special characters for that field (, - * /).
##
## Example usage::
##
##     import schedules, times, asyncdispatch
##     schedules:
##       cron(minute="*/1", hour="*", day_of_month="*", month="*", day_of_week="*", id="tick"):
##         echo("tick", now())
##       cron(minute="*/1", hour="*", day_of_month="*", month="*", day_of_week="*", id="atick", async=true):
##         echo("tick", now())
##         await sleepAsync(3000)
##
## The code enables you:
##
## * Schedule thread proc every minute.
## * Schedule async proc every minute.
##
## Run::
##
##     nim c --threads:on -r cronExample.nim
##
## Note:
##
## * Don't forget --threads:on when compiling your application.
## * The library schedules all jobs at a regular interval, but it'll be impacted by your system load.
##
## ## Throttling
##
## By default, only one instance of the job is to be scheduled at the same time. If a job hasn't finished but the next run time has come, the next job will not be scheduled.
##
## You can allow more instances by specifying `throttle=`. For example::
##
##     import schedules, times, asyncdispatch
##
##     schedules:
##       every(seconds=1, id="tick", throttle=2, async=true):
##         echo("async tick ", now())
##         await sleepAsync(2000)
##       every(seconds=1, id="tick", throttle=2):
##         echo("sync tick ", now())
##
##
## ## Customize Scheduler
##
## Sometimes, you want to run the scheduler in parallel with other libraries. In this case, you can create your own scheduler by macro scheduler and start it later.
##
## Below is an example of co-exist jester and nim-schedules in one process.::
##
##     import times, asyncdispatch, schedules, jester
##
##     scheduler mySched:
##       every(seconds=1, id="sync tick"):
##         echo("sync tick, seconds=1 ", now())
##
##     router myRouter:
##       get "/":
##         resp "It's alive!"
##
##     proc main():
##       # start schedules
##       asyncCheck mySched.start()
##
##       # start jester
##       let port = paramStr(1).parseInt().Port
##       let settings = newSettings(port=port)
##       var jester = initJester(myrouter, settings=settings)
##
##       # run
##       jester.serve()
##
##     when isMainModule:
##       main()
##
## ## Set Start Time and End Time
##
## You can limit the schedules running in a designated range of time by specifying startTime and endTime.
##
## For example::
##
##     import schedules, times, asyncdispatch, os
##
##     scheduler demoSetRange:
##       every(
##         seconds=1,
##         id="tick",
##         startTime=initDateTime(2019, 1, 1),
##         endTime=now()+initDuration(seconds=10)
##       ):
##         echo("tick", now())
##
##     when isMainModule:
##       waitFor demoSetRange.start()
##
## Parameters startTime and endTime can be used independently. For example, you can set startTime only, or set endTime only.


import schedules/scheduler
import schedules/cron/cron

export logger
export BeaterAsyncProc
export BeaterThreadProc
export Throttler
export initThrottler
export throttled
export submit
export BeaterKind
export Beater
export `$`
export initBeater
export fireTime
export fire
export Settings
export newSettings
export Scheduler
export initScheduler
export register
export idle
export start
export serve
export waitFor
export scheduler
export schedules
export Cron
export newCron
export getNext
