# This is just an example to get you started. You may wish to put all of your
# tests into a single file, or separate them into multiple `test1`, `test2`
# etc. files (better names are recommended, just make sure the name starts with
# the letter 't').
#
# To run these tests, simply execute `nimble test`.

import unittest

import times, options
import scheduler

test "IntervalBeater.$":
  let beater = initBeater(TimeInterval(seconds: 1))
  check $beater == "Beater(bkInterval,1 second)"

test "IntervalBeater.fireTime | startTime hasn't come":
  let current = now().utc()
  let beater = initBeater(
    initTimeInterval(seconds=10),
    startTime=some(current + initTimeInterval(seconds=4))
  )
  let expect = current + initTimeInterval(seconds=4)
  let actual = beater.fireTime(none(DateTime), current).get()
  check actual == expect

test "IntervalBeater.fireTime | startTime has come":
  let current = now().utc()
  let beater = initBeater(
    initTimeInterval(seconds=10),
    startTime=some(current - initTimeInterval(seconds=14))
  )
  let expect = current + initTimeInterval(seconds=6)
  let actual = beater.fireTime(none(DateTime), current).get()
  check actual == expect

test "IntervalBeater.fireTime | startTime has come 2":
  let current = now().utc()
  let beater = initBeater(
    initTimeInterval(seconds=10),
    startTime=some(current - initTimeInterval(seconds=4))
  )
  let expect = current + initTimeInterval(seconds=6)
  let actual = beater.fireTime(none(DateTime), current).get()
  check actual == expect

test "IntervalBeater.fireTime | some prev":
  let current = now().utc()
  let beater = initBeater(initTimeInterval(seconds=10))
  let prev = some(current - initTimeInterval(seconds=4))
  let actual = beater.fireTime(prev, current).get()
  let expect = current + initTimeInterval(seconds=6)
  check actual == expect
