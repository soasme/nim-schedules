from options import Option, some, none, get, isNone
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
    none(int)


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
    none(int)


proc getNextForAll*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  let fieldMin = field.minValue(dt)
  let fieldMax = field.maxValue(dt)
  let nextVal = max(field.getValue(dt), fieldMin)
  if nextVal <= fieldMax:
    some(nextVal)
  else:
    none(int)


proc getNextForStepAll*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  let fieldMin = field.minValue(dt)
  let fieldMax = field.maxValue(dt)
  var nextVal = max(field.getValue(dt), fieldMin)
  let offset = expr.step - (nextVal - fieldMin) mod expr.step
  nextVal += offset
  if nextVal <= fieldMax:
    some(nextVal)
  else:
    none(int)


proc getNextForNum*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  let nextVal = field.getValue(dt)
  if nextVal <= expr.num:
    some(nextVal)
  else:
    none(int)


proc getNextForSeq*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  result = none(int)
  for subExpr in expr.exprs:
    let next = getNext(subExpr, field, dt)
    if next.isNone:
      continue
    if result.isNone:
      result = next
      continue
    result = some(min(result.get, next.get))


# TODO: getNextForAny
# TODO: getNextForSeq
# TODO: getNextForHash
# TODO: getNextForNearest

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


type
  Cron* = object
    start_time*: DateTime
    end_time*: DateTime
    year*: Field
    month*: Field
    day*: Field
    week*: Field
    day_of_week*: Field
    hour*: Field
    minute*: Field
    second*: Field


proc newCron*(
  start_time: DateTime,
  end_time: DateTime,
  year: string = "*",
  month: string = "*",
  day: string = "*",
  day_of_week: string = "*",
  hour: string = "*",
  minute: string = "*",
  second: string = "*",
): Cron =
  Cron(
    start_time: start_time,
    end_time: end_time,
    year: Field(kind: fkYear, expr: parseYears(year)),
    month: Field(kind: fkMonth, expr: parseMonths(month)),
    day: Field(kind: fkDayOfMonth, expr: parseDayOfMonths(day)),
    day_of_week: Field(kind: fkDayOfWeek, expr: parseDayOfWeeks(day_of_week)),
    hour: Field(kind: fkHour, expr: parseHours(hour)),
    minute: Field(kind: fkMinute, expr: parseMinutes(minute)),
    second: Field(kind: fkSecond, expr: parseSeconds(second)),
  )


when isMainModule:
  let dt = now()

  var e = newLastExpr()
  var f = Field(kind: fkDayOfMonth, expr: e)
  echo getNext(e, f, dt).get

  e = parseDayOfWeeks("4#3")
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
