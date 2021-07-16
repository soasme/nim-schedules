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

import schedulespkg/scheduler
import schedulespkg/cron/cron

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
