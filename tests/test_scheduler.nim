import unittest

import os, times, options, asyncdispatch
import schedules

scheduler mySched:
  every(seconds=1, id="sync tick"):
    echo("sync tick, seconds=1 ", now())

  every(seconds=1, id="async tick", async=true):
    echo("async tick, seconds=1 ", now())

when isMainModule:
  mySched.serve()
