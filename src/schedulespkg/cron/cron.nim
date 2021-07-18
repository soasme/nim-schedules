from options import Option, some, none, get, isNone
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
  let fieldVal = field.getValue(dt)
  let fieldMin = field.minValue(dt)
  let fieldMax = field.maxValue(dt)
  var nextVal = max(fieldVal, fieldMin)
  let offset = (expr.step - (fieldVal - fieldMin)) mod expr.step
  nextVal += offset
  if nextVal <= fieldMax:
    some(nextVal)
  else:
    none(int)


proc getNextForNum*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  let fieldValue = field.getValue(dt)
  if fieldValue <= expr.num:
    some(expr.num)
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

proc getMinIter*(expr: Expr, field: Field, dt: DateTime): Option[int] =
  case expr.kind
  of ekNum: some(expr.num)
  of ekIndex: some(expr.index)
  of ekAll: some(field.getValue(dt))
  of ekRange: some(expr.rangeSlice.a)
  of ekSeq:
    var minVal = field.maxValue(dt)
    for subExpr in expr.exprs:
      minVal = min(minVal, subExpr.getMinIter(field, dt).get)
    some(minVal)
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
  var startTime = dt.ceil
  var offset: Duration

  let someMinuteOfNextFire = cron.fields[fkMinute].getNext(startTime)
  offset = if someMinuteOfNextFire.isNone:
    initDuration(
      minutes=(
        cron.fields[fkMinute].maxValue(startTime) -
        cron.fields[fkMinute].getValue(startTime) +
        cron.fields[fkMinute].expr.getMinIter(cron.fields[fkMinute], startTime).get
      )
    )
  elif someMinuteOfNextFire.get < cron.fields[fkMinute].getValue(startTime):
    initDuration(
      minutes=(
        cron.fields[fkMinute].maxValue(startTime) -
        cron.fields[fkMinute].getValue(startTime) +
        someMinuteOfNextFire.get
      )
    )
  else:
    initDuration(minutes=someMinuteOfNextFire.get - cron.fields[fkMinute].getValue(startTime))

  # echo(("minute offset", offset))

  startTime += offset

  let someHourOfNextFire = cron.fields[fkHour].getNext(startTime)
  offset = if someHourOfNextFire.isNone:
    initDuration(
      hours=(
        cron.fields[fkHour].maxValue(startTime) -
        cron.fields[fkHour].getValue(startTime) +
        cron.fields[fkHour].expr.getMinIter(cron.fields[fkHour], startTime).get
      )
    )
  elif someHourOfNextFire.get < cron.fields[fkHour].getValue(dt):
    initDuration(
      hours=(
        cron.fields[fkHour].maxValue(startTime) -
        cron.fields[fkHour].getValue(startTime) +
        someHourOfNextFire.get
      )
    )
  else:
    initDuration(hours=someHourOfNextFire.get - cron.fields[fkHour].getValue(startTime))

  # echo(("hour offset", offset))

  startTime += offset

  let someDayOfMonthOfNextFire = cron.fields[fkDayOfMonth].getNext(startTime)
  let dayOfMonthOffset = if someDayOfMonthOfNextFire.isNone:
    initDuration(
      days=(
        cron.fields[fkDayOfMonth].maxValue(startTime) -
        cron.fields[fkDayOfMonth].getValue(startTime) +
        cron.fields[fkDayOfMonth].expr.getMinIter(cron.fields[fkDayOfMonth], startTime).get
      )
    )
  elif someDayOfMonthOfNextFire.get < cron.fields[fkDayOfMonth].getValue(startTime):
    initDuration(
      days=(
        cron.fields[fkDayOfMonth].maxValue(startTime) -
        cron.fields[fkDayOfMonth].getValue(startTime) +
        someDayOfMonthOfNextFire.get
      )
    )
  else:
    initDuration(days=someDayOfMonthOfNextFire.get - cron.fields[fkDayOfMonth].getValue(startTime))

  let someDayOfWeekOfNextFire = cron.fields[fkDayOfWeek].getNext(startTime)
  let dayOfWeekOffset = if someDayOfWeekOfNextFire.isNone:
    initDuration(
      days=(
        cron.fields[fkDayOfWeek].maxValue(dt) -
        cron.fields[fkDayOfWeek].getValue(dt) +
        cron.fields[fkDayOfWeek].expr.getMinIter(cron.fields[fkDayOfWeek], startTime).get
      )
    )
  elif someDayOfWeekOfNextFire.get < cron.fields[fkDayOfWeek].getValue(dt):
    initDuration(
      days=(
        cron.fields[fkDayOfWeek].maxValue(dt) -
        cron.fields[fkDayOfWeek].getValue(dt) +
        someDayOfWeekOfNextFire.get
      )
    )
  else:
    initDuration(days=someDayOfWeekOfNextFire.get - cron.fields[fkDayOfWeek].getValue(dt))

  offset = if cron.fields[fkDayOfWeek].expr.kind == ekAll:
    dayOfMonthOffset
  elif cron.fields[fkDayOfMonth].expr.kind == ekAll:
    dayOfWeekOffset
  else:
    min(dayOfMonthOffset, dayOfWeekOffset)

  # echo(("day offset", offset, cron.fields[fkDayOfWeek].expr.kind, cron.fields[fkDayOfMonth].expr.kind))

  startTime += offset

  let someMonthOfNextFire = cron.fields[fkMonth].getNext(startTime)
  let monthOffset = if someMonthOfNextFire.isNone:
    initTimeInterval(
      months=(
        cron.fields[fkMonth].maxValue(startTime) -
        cron.fields[fkMonth].getValue(startTime) +
        cron.fields[fkMonth].expr.getMinIter(cron.fields[fkMonth], startTime).get
      )
    )
  elif someMonthOfNextFire.get < cron.fields[fkMonth].getValue(startTime):
    initTimeInterval(
      months=(
        cron.fields[fkMonth].maxValue(dt) -
        cron.fields[fkMonth].getValue(dt) +
        someMonthOfNextFire.get
      )
    )
  else:
    initTimeInterval(months=someMonthOfNextFire.get - cron.fields[fkMonth].getValue(startTime))

  # echo(("month offset", monthOffset))
  startTime += monthOffset

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
