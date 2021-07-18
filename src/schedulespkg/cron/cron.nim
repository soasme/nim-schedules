from options import Option, some, none, get, isNone, isSome
from algorithm import sorted
import tables
import times

import ./expr
import ./parser
import ./field


proc getNext*(expr: Expr, field: Field, dt: DateTime): Option[int];


proc getNextForLastDayOfMonth*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  some(getDaysInMonth(dt.month, dt.year))


proc getNextForLastDayOfWeek*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  # TODO:
  # algorithm:
  #   get day of week for the last day in month
  #   -(7-n).
  none(int)


# TODO: rename index to nthdayofweek
proc getNextForIndex*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  var firstDayForIndex = expr.indexer - ord(getDayOfWeek(1, dt.month, dt.year))
  if firstDayForIndex <= 0:
    firstDayForIndex += 7

  let nextIndex = firstDayForIndex + (expr.index-1) * 7
  let daysInMonth = getDaysInMonth(dt.month, dt.year)

  if nextIndex <= daysInMonth and nextIndex >= dt.monthday:
    some(nextIndex)
  else:
    none(int)


proc getNextForRange*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  let fieldVal = field.getValue(dt)
  let fieldMin = max(field.minValue(dt), expr.rangeSlice.a)
  let fieldMax = min(field.maxValue(dt), expr.rangeSlice.b)

  let nextVal = max(fieldMin, fieldVal)

  if nextVal <= fieldMax:
    some(nextVal)
  else:
    some(expr.rangeSlice.a)


proc getNextForStepRange*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  let fieldVal = field.getValue(dt)
  let fieldMin = max(field.minValue(dt), expr.stepExpr.rangeSlice.a)
  let fieldMax = min(field.maxValue(dt), expr.stepExpr.rangeSlice.b)

  var nextVal = max(fieldMin, fieldVal)
  let offset = expr.step - (nextVal - fieldMin) mod expr.step
  nextVal += offset

  if nextVal <= fieldMax:
    some(nextVal)
  else:
    some(expr.stepExpr.rangeSlice.a)


proc getNextForAll*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  let fieldMin = field.minValue(dt)
  let fieldMax = field.maxValue(dt)
  let nextVal = max(field.getValue(dt), fieldMin)
  if nextVal <= fieldMax:
    some(nextVal)
  else:
    some(fieldMin)


proc getNextForStepAll*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  let fieldVal = field.getValue(dt)
  let fieldMin = field.minValue(dt)
  let fieldMax = field.maxValue(dt)
  var nextVal = max(fieldVal, fieldMin)
  let offset = (expr.step - (fieldVal - fieldMin)) mod expr.step
  nextVal += offset
  if nextVal <= fieldMax:
    some(nextVal)
  else:
    some(fieldMin)


proc getNextForNum*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  some(expr.num)


proc getNextForSeq*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  var nexts: seq[int]
  for subExpr in expr.exprs:
    let next = getNext(subExpr, field, dt)
    if next.isSome:
      nexts.add(next.get)

  if nexts.len == 0:
    return none(int)

  nexts = sorted(nexts)

  let fieldVal = field.getValue(dt)
  for next in nexts:
    if next >= fieldVal:
      return some(next)

  return some(nexts[0])


# TODO: getNextForAny
# TODO: getNextForSeq
# TODO: getNextForHash
# TODO: getNextForNearest

proc getMinIter*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  case expr.kind
  else: none(int)


proc getNext*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  case expr.kind
  of ekNum: getNextForNum(expr, field, dt)
  of ekIndex: getNextForIndex(expr, field, dt)
  of ekAll: getNextForAll(expr, field, dt)
  of ekRange: getNextForRange(expr, field, dt)
  of ekSeq: getNextForSeq(expr, field, dt)
  of ekStep:
    case expr.stepExpr.kind
    of ekAll: getNextForStepAll(expr, field, dt)
    of ekRange: getNextForStepRange(expr, field, dt)
    else: none(int)
  of ekLast:
    case field.kind
    of fkDayOfMonth: getNextForLastDayOfMonth(expr, field, dt)
    of fkDayOfWeek: getNextForLastDayOfWeek(expr, field, dt)
    else: none(int)
  else: none(int)


proc getNext*(field: Field, dt: DateTime): Option[int] = 
  getNext(field.expr, field, dt)


type
  Cron* = object
    fields: Table[FieldKind, Field]


proc newCron*(
  second: string = "*",
  minute: string = "*",
  hour: string = "*",
  day_of_month: string = "*",
  day_of_week: string = "*",
  month: string = "*",
  year: string = "*",
): Cron =
  Cron(
    fields: {
      fkYear: Field(kind: fkYear, expr: parseYears(year)),
      fkMonth: Field(kind: fkMonth, expr: parseMonths(month)),
      fkDayOfMonth: Field(kind: fkDayOfMonth, expr: parseDayOfMonths(day_of_month)),
      fkDayOfWeek: Field(kind: fkDayOfWeek, expr: parseDayOfWeeks(day_of_week)),
      fkHour: Field(kind: fkHour, expr: parseHours(hour)),
      fkMinute: Field(kind: fkMinute, expr: parseMinutes(minute)),
      fkSecond: Field(kind: fkSecond, expr: parseSeconds(second)),
    }.toTable
  )


proc ceil(dt: DateTime): DateTime =
  result = dt
  if dt.nanosecond > 0:
    result -= initTimeInterval(nanoseconds=dt.nanosecond)
    result += initTimeInterval(seconds=1)


proc initDateTime(values: ref Table[FieldKind, int]): DateTime =
  initDateTime(
    MonthdayRange(values[fkDayOfMonth]),
    Month(values[fkMonth]),
    values[fkYear],
    values[fkHour],
    values[fkMinute],
    values[fkSecond],
  )

proc getNext*(cron: Cron, dt: DateTime): Option[DateTime] =
  # Given a cron object and a datetime, calculate the next fire time.
  var startTime = dt.ceil
  var offset: Duration

  let someMinuteOfNextFire = cron.fields[fkMinute].getNext(startTime)
  var minutesOffset = someMinuteOfNextFire.get - cron.fields[fkMinute].getValue(startTime)
  if minutesOffset < 0:
    minutesOffset += cron.fields[fkMinute].maxValue(startTime)

  startTime += initDuration(minutes=minutesOffset)

  let someHourOfNextFire = cron.fields[fkHour].getNext(startTime)
  var hoursOffset = someHourOfNextFire.get - cron.fields[fkHour].getValue(startTime)
  if hoursOffset < 0:
    hoursOffset += cron.fields[fkHour].maxValue(startTime)

  startTime += initDuration(hours=hoursOffset)

  let someDayOfMonthOfNextFire = cron.fields[fkDayOfMonth].getNext(startTime)
  var dayOfMonthOffset = someDayOfMonthOfNextFire.get - cron.fields[fkDayOfMonth].getValue(startTime)
  if dayOfMonthOffset < 0:
    dayOfMonthOffset += cron.fields[fkDayOfMonth].maxValue(startTime)

  let someDayOfWeekOfNextFire = cron.fields[fkDayOfWeek].getNext(startTime)
  var dayOfWeekOffset = someDayOfWeekOfNextFire.get - cron.fields[fkDayOfWeek].getValue(dt)
  if dayOfWeekOffset < 0:
    dayOfWeekOffset += cron.fields[fkDayOfWeek].maxValue(dt)

  # The dom/dow situation is odd.
  # When dom/dow are both set, cron run next dom AND next dow.
  # Otherwise, run only next dom OR next dow.
  #
  # Quoted cron.c:
  # > yes, it's bizarre. like many bizarre things, it's the standard.
  let daysOffset = if cron.fields[fkDayOfWeek].expr.kind == ekAll:
    dayOfMonthOffset
  elif cron.fields[fkDayOfMonth].expr.kind == ekAll:
    dayOfWeekOffset
  else:
    min(dayOfMonthOffset, dayOfWeekOffset)

  startTime += initDuration(days=daysOffset)

  let someMonthOfNextFire = cron.fields[fkMonth].getNext(startTime)
  var monthOffset = someMonthOfNextFire.get - cron.fields[fkMonth].getValue(startTime)
  if monthOffset < 0:
    monthOffset += cron.fields[fkMonth].maxValue(dt)

  startTime += initTimeInterval(months=monthOffset)

  result = some(startTime)

when isMainModule:
  let dt = now()

  var e = newLastExpr()
  var f = Field(kind: fkDayOfMonth, expr: e)
  echo getNext(e, f, dt).get

  e = parseDayOfWeeks("4#4")
  f = Field(kind: fkDayOfWeek, expr: e)
  echo getNext(e, f, dt).get

  e = parseHours("0-23")
  f = Field(kind: fkHour, expr: e)
  echo getNext(e, f, dt).get

  e = parseMonths("1-12/2")
  f = Field(kind: fkMonth, expr: e)
  echo getNext(e, f, dt).get

  e = parseMonths("*")
  f = Field(kind: fkMonth, expr: e)
  echo getNext(e, f, dt).get

  e = parseMonths("*/2")
  f = Field(kind: fkMonth, expr: e)
  echo getNext(e, f, dt).get

  e = parseHours("1-3,22-23,1-12/2")
  f = Field(kind: fkHour, expr: e)
  echo getNext(e, f, dt).get

  var cron = newCron(minute="*/1")
  echo cron.getNext(dt).get

  cron = newCron(minute="*/2")
  echo cron.getNext(dt).get

  cron = newCron(minute="*/3")
  echo cron.getNext(dt).get

  cron = newCron(hour="*/2")
  echo cron.getNext(dt).get

  cron = newCron(hour="*/3")
  echo cron.getNext(dt).get

  cron = newCron(hour="*/4")
  echo cron.getNext(dt).get
