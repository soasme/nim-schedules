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
  let beater = IntervalBeater(interval: TimeInterval(seconds: 1))
  let asOf = 100.fromUnix.utc
  let prev = 0.fromUnix.utc
  check beater.nextTime(asOf, prev) == 1.fromUnix.utc
