import unittest
import options
import times
import schedules

template checkSome(v: untyped, o: untyped) =
  let r = v
  check r.isSome
  check r.get == o

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


test "* 8-10 * feb-dec * 2000":
  let cron = newCron(
    hour="8-10",
    month="feb-dec",
    year="2000",
  )
  let dt = initDateTime(1, mJan, 2000, 0, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(1, mFeb, 2000, 8, 0, 0)
  )


test "5 4 * * *":
  let cron = newCron(
    minute="5",
    hour="4",
  )
  let dt = initDateTime(1, mJan, 2000, 0, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(1, mJan, 2000, 4, 5, 0)
  )


test "5 0 * 8 *":
  let cron = newCron(
    minute="5",
    hour="0",
    month="8",
  )
  let dt = initDateTime(1, mJan, 2000, 0, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(1, mAug, 2000, 0, 5, 0)
  )


test "15 14 1 * *":
  let cron = newCron(
    minute="15",
    hour="14",
    day_of_month="1",
  )
  let dt = initDateTime(1, mJan, 2000, 14, 15, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(1, mJan, 2000, 14, 15, 0)
  )


test "0 22 * * 1-5":
  let cron = newCron(
    minute="0",
    hour="22",
    day_of_week="1-5"
  )
  let dt = initDateTime(1, mJan, 2000, 0, 0, 0) # sat

  checkSome(
    cron.getNext(dt),
    initDateTime(1, mJan, 2000, 22, 0, 0)
  )

test "0 22 * * tue-sat":
  let cron = newCron(
    minute="0",
    hour="22",
    day_of_week="tue-sat"
  )
  let dt = initDateTime(1, mJan, 2000, 0, 0, 0) # sat

  checkSome(
    cron.getNext(dt),
    initDateTime(1, mJan, 2000, 22, 0, 0)
  )


test "0 22 * * tue-thu":
  let cron = newCron(
    minute="0",
    hour="22",
    day_of_week="tue-thu"
  )
  let dt = initDateTime(1, mJan, 2000, 0, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(4, mJan, 2000, 22, 0, 0)
  )


test "23 0-20/2 * * *":
  let cron = newCron(
    minute="23",
    hour="0-20/2",
  )
  let dt = initDateTime(1, mJan, 2000, 13, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(1, mJan, 2000, 14, 23, 0)
  )


test "5 4 * * sun":
  let cron = newCron(
    minute="5",
    hour="4",
    day_of_week="sun",
  )
  let dt = initDateTime(1, mJan, 2000, 0, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(2, mJan, 2000, 4, 5, 0)
  )


test "0 0,12 1 */2 *":
  let cron = newCron(
    minute="0",
    hour="0,12",
    day_of_month="1",
    month="*/2",
  )

  let dt = initDateTime(1, mJan, 2000, 0, 0, 0)
  checkSome(
    cron.getNext(dt),
    initDateTime(1, mJan, 2000, 0, 0, 0)
  )

  let dt2 = initDateTime(1, mJan, 2000, 1, 0, 0)
  checkSome(
    cron.getNext(dt2),
    initDateTime(1, mJan, 2000, 12, 0, 0)
  )

  let dt3 = initDateTime(2, mJan, 2000, 0, 0, 0)
  checkSome(
    cron.getNext(dt3),
    initDateTime(1, mMar, 2000, 0, 0, 0)
  )


test "0 4 8-14 * *":
  let cron = newCron(
    minute="0",
    hour="4",
    day_of_month="8-14",
  )
  let dt = initDateTime(1, mJan, 2000, 0, 0, 0)

  checkSome(
    cron.getNext(dt),
    initDateTime(8, mJan, 2000, 4, 0, 0)
  )


test "0 0 1,15 * Thu":
  let cron = newCron(
    minute="0",
    hour="0",
    day_of_month="1,15",
    day_of_week="Thu",
  )

  let dt = initDateTime(1, mJan, 2000, 0, 0, 0)
  checkSome(
    cron.getNext(dt),
    initDateTime(1, mJan, 2000, 0, 0, 0)
  )

test "0 0 1,15 * Thu":
  let cron = newCron(
    minute="0",
    hour="0",
    day_of_month="1,15",
    day_of_week="Thu",
  )

  let dt = initDateTime(2, mJan, 2000, 0, 0, 0)
  checkSome(
    cron.getNext(dt),
    initDateTime(6, mJan, 2000, 0, 0, 0)
  )
