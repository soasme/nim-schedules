import unittest

import os, times, options, asyncdispatch
import schedules


test "endTime":

  scheduler testEndTime:
    every(seconds=1, id="sync tick", endTime=now()+initDuration(seconds=2)):
      echo("sync tick, seconds=1 ", now())

    every(seconds=1, id="async tick", async=true, endTime=now()+initDuration(seconds=2)):
      echo("async tick, seconds=1 ", now())

  proc main(): Future[bool] {.async.} =
    await testEndTime.start()
    return true

  check (waitFor(main()))
