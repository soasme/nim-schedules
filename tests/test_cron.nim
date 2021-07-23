import unittest
import options
import times
import schedules
import schedules/cron/parser
import schedules/cron/expr

proc checkCron(cron: Cron, start: string, expect: string) =
  let dt = parse(start, "yyyy-MM-dd HH:mm:ss")
  let v = cron.getNext(dt)
  check v.isSome
  check v.get == parse(expect, "yyyy-MM-dd HH:mm:ss")

test "cron parser":
  check $parseMinutes("*") == "*"
  check $parseMinutes("*/2") == "*/2"
  check $parseMinutes("*/59") == "*/59"
  check $parseMinutes("0") == "0"
  check $parseMinutes("0/2") == "0/2"
  check $parseMinutes("0,1,2") == "0,1,2"
  check $parseMinutes("0-59") == "0-59"
  check $parseMinutes("0-59/2") == "0-59/2"
  check $parseHours("*") == "*"
  check $parseHours("*/2") == "*/2"
  check $parseHours("*/23") == "*/23"
  check $parseHours("0") == "0"
  check $parseHours("0,1,2") == "0,1,2"
  check $parseHours("0-23") == "0-23"
  check $parseHours("0-23/2") == "0-23/2"
  check $parseDayOfMonths("*") == "*"
  check $parseDayOfMonths("*/2") == "*/2"
  check $parseDayOfMonths("*/15") == "*/15"
  check $parseDayOfMonths("1,2,3") == "1,2,3"
  check $parseDayOfMonths("1-23") == "1-23"
  check $parseDayOfMonths("1-23/2") == "1-23/2"
  check $parseDayOfMonths("l") == "L"
  check $parseDayOfMonths("last") == "L"
  check $parseDayOfMonths("12w") == "12W"
  check $parseDayOfMonths("12W") == "12W"
  check $parseMonths("*") == "*"
  check $parseMonths("*/2") == "*/2"
  check $parseMonths("*/3") == "*/3"
  check $parseMonths("1,2,3") == "1,2,3"
  check $parseMonths("1-12") == "1-12"
  check $parseMonths("1-12/2") == "1-12/2"
  check $parseMonths("jan,feb,mar,apr") == "1,2,3,4"
  check $parseMonths("jan-dec") == "1-12"
  check $parseMonths("jan-dec/2") == "1-12/2"
  check $parseMonths("Jan,Feb,Mar,Apr") == "1,2,3,4"
  check $parseMonths("JAN-DEC") == "1-12"
  check $parseMonths("JAN-DEC/2") == "1-12/2"
  check $parseDayOfWeeks("*") == "*"
  check $parseDayOfWeeks("?") == "?"
  check $parseDayOfWeeks("*/2") == "*/2"
  check $parseDayOfWeeks("*/3") == "*/3"
  check $parseDayOfWeeks("1,2,3") == "1,2,3"
  check $parseDayOfWeeks("1-6") == "1-6"
  check $parseDayOfWeeks("1-6/2") == "1-6/2"
  check $parseDayOfWeeks("mon,tue,wed,thu,fri,sat,sun") == "1,2,3,4,5,6,7"
  check $parseDayOfWeeks("mon-sun") == "1-7"
  check $parseDayOfWeeks("mon-sun/2") == "1-7/2"
  check $parseDayOfWeeks("MON,TUE,WED,THU,FRI,SAT,SUN") == "1,2,3,4,5,6,7"
  check $parseDayOfWeeks("MON-SUN") == "1-7"
  check $parseDayOfWeeks("MON-SUN/2") == "1-7/2"
  check $parseDayOfWeeks("1l") == "1L"
  check $parseDayOfWeeks("1L") == "1L"
  check $parseDayOfWeeks("1#3") == "1#3"
  check $parseDayOfWeeks("1#5") == "1#5"
  check $parseYears("*") == "*"
  check $parseYears("2020,2021") == "2020,2021"
  check $parseYears("2020-2021") == "2020-2021"


test "* * 1-6 * *":
  let cron = newCron(month="1-6")
  cron.checkCron(
    "1999-12-01 00:00:00",
    "2000-01-01 00:00:00"
  )


test "* * jan-jun * *":
  let cron = newCron(month="jan-jun")
  cron.checkCron(
    "1999-12-01 00:00:00",
    "2000-01-01 00:00:00"
  )


test "* * 10-13 1-6 *":
  let cron = newCron(month="1-6", day_of_month="10-13")
  cron.checkCron(
    "1999-12-01 00:00:00",
    "2000-01-10 00:00:00"
  )


test "* 8-10 * feb-dec * 2000":
  let cron = newCron(hour="8-10", month="feb-dec", year="2000")
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-02-01 08:00:00",
  )


test "5 4 * * *":
  let cron = newCron(minute="5", hour="4")
  cron.checkCron(
    "2020-01-01 00:00:00",
    "2020-01-01 04:05:00",
  )


test "5 0 * 8 *":
  let cron = newCron(minute="5", hour="0", month="8")
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-08-01 00:05:00"
  )


test "15 14 1 * *":
  let cron = newCron(minute="15", hour="14", day_of_month="1")
  cron.checkCron(
    "2000-01-01 14:15:00",
    "2000-01-01 14:15:00"
  )


test "0 22 * * 1-5":
  let cron = newCron(minute="0", hour="22", day_of_week="1-5")
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-03 22:00:00",
  )


test "0 22 * * tue-sat":
  let cron = newCron(minute="0", hour="22", day_of_week="tue-sat")
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-01 22:00:00",
  )


test "0 22 * * tue-thu":
  let cron = newCron(minute="0", hour="22", day_of_week="tue-thu")
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-04 22:00:00",
  )


test "23 0-20/2 * * *":
  let cron = newCron(minute="23", hour="0-20/2")
  cron.checkCron(
    "2000-01-01 13:00:00",
    "2000-01-01 14:23:00",
  )
  cron.checkCron(
    "2000-01-01 13:00:00",
    "2000-01-01 14:23:00",
  )


test "23 1/3 * * *":
  let cron = newCron(minute="23", hour="1/3")
  cron.checkCron(
    "2000-01-01 13:00:00",
    "2000-01-01 13:23:00",
  )
  cron.checkCron(
    "2000-01-01 13:23:00",
    "2000-01-01 13:23:00",
  )
  cron.checkCron(
    "2000-01-01 13:23:01",
    "2000-01-01 16:23:00",
  )


test "0 0,12 1 */2 *":
  let cron = newCron(
    minute="0",
    hour="0,12",
    day_of_month="1",
    month="*/2",
  )

  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-01 01:00:00",
    "2000-01-01 12:00:00",
  )
  cron.checkCron(
    "2000-01-02 00:00:00",
    "2000-03-01 00:00:00",
  )


test "0 4 8-14 * *":
  let cron = newCron(
    minute="0",
    hour="4",
    day_of_month="8-14",
  )
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-08 04:00:00"
  )


test "0 0 1,15 * Thu":
  let cron = newCron(
    minute="0",
    hour="0",
    day_of_month="1,15",
    day_of_week="Thu",
  )
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-02 00:00:00",
    "2000-01-06 00:00:00",
  )


test "* * 5-13 1/3 * 2009/2":
  let cron = newCron(
    year="2009/2",
    month="1/3",
    day_of_month="5-13",
  )
  cron.checkCron(
    "2008-12-01 00:00:00",
    "2009-01-05 00:00:00",
  )
  cron.checkCron(
    "2009-10-14 00:00:00",
    "2011-01-05 00:00:00",
  )


test "*/1 * * * *":
  let cron = newCron(
    minute="*/1"
  )
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-01 00:00:01",
    "2000-01-01 00:01:00",
  )
  cron.checkCron(
    "2000-01-01 00:00:59",
    "2000-01-01 00:01:00",
  )
  cron.checkCron(
    "2000-01-01 00:01:00",
    "2000-01-01 00:01:00",
  )
  cron.checkCron(
    "1999-12-31 23:59:59",
    "2000-01-01 00:00:00",
  )


test "*/5 * * * *":
  let cron = newCron(
    minute="*/5"
  )
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-01 00:00:01",
    "2000-01-01 00:05:00",
  )
  cron.checkCron(
    "2000-01-01 00:04:59",
    "2000-01-01 00:05:00",
  )
  cron.checkCron(
    "1999-12-31 23:55:01",
    "2000-01-01 00:00:00",
  )



test "0 */1 * * *":
  let cron = newCron(minute="0", hour="*/1")
  cron.checkCron(
    "1999-12-31 23:59:59",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-01 00:00:01",
    "2000-01-01 01:00:00",
  )
  cron.checkCron(
    "2000-01-01 00:59:59",
    "2000-01-01 01:00:00",
  )



test "0 */3 * * *":
  let cron = newCron(minute="0", hour="*/3")
  cron.checkCron(
    "1999-12-31 23:59:59",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-01 00:00:01",
    "2000-01-01 03:00:00",
  )
  cron.checkCron(
    "2000-01-01 02:59:59",
    "2000-01-01 03:00:00",
  )


test "0 0 */3 * *":
  let cron = newCron(minute="0", hour="0", day_of_month="*/3")
  cron.checkCron(
    "1999-12-31 23:59:59",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-01 00:00:00",
  )
  cron.checkCron(
    "2000-01-01 00:00:01",
    "2000-01-04 00:00:00",
  )
  cron.checkCron(
    "2000-01-03 23:59:59",
    "2000-01-04 00:00:00",
  )
  cron.checkCron(
    "2000-02-27 00:00:00",
    "2000-02-28 00:00:00",
  )
  cron.checkCron(
    "2000-02-28 00:00:01",
    "2000-03-02 00:00:00",
  )


test "5 4 * * sun":
  let cron = newCron(minute="5", hour="4", day_of_week="sun")
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-02 04:05:00",
  )


test "5 4 1 * sun":
  let cron = newCron(minute="5", hour="4", day_of_month="1", day_of_week="sun")
  cron.checkCron(
    "2000-01-01 00:00:00",
    "2000-01-01 04:05:00",
  )
  cron.checkCron(
    "2000-01-01 12:00:00",
    "2000-01-02 04:05:00",
  )
  cron.checkCron(
    "2000-01-02 12:00:00",
    "2000-01-09 04:05:00",
  )
  cron.checkCron(
    "2000-02-29 12:00:00",
    "2000-03-01 04:05:00",
  )
