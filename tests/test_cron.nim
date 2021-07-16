import unittest
import options
import times
import schedules

template checkSome(v: untyped, o: untyped) =
  check v.isSome
  check v.get == o

test "* * 1-6 * *":
  let cron = newCron(month="1-6")
  let dt = initDateTime(1, mDec, 1999, 0, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(1, mJan, 2000, 0, 0, 0)
  )

test "* * jan-jun * *":
  let cron = newCron(month="jan-jun")
  let dt = initDateTime(1, mDec, 1999, 0, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(1, mJan, 2000, 0, 0, 0)
  )


test "* * 10-13 1-6 *":
  let cron = newCron(
    month="1-6",
    day_of_month="10-13",
  )
  let dt = initDateTime(1, mDec, 1999, 0, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(10, mJan, 2000, 0, 0, 0)
  )
