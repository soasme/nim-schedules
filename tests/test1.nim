# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import times
import scheduler

test "IntervalBeater: next time":
  let beater = initIntervalBeater(TimeInterval(seconds: 1))
  let prev = 0.fromUnix.utc
  let now = 100.fromUnix.utc
  check beater.fireTime(prev, now) == 1.fromUnix.utc

test "IntervalBeater: $":
  let beater = initIntervalBeater(TimeInterval(seconds: 1))
  check $beater == "IntervalBeater(1 second)"
