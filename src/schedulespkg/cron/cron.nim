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


proc setNext(cron: Cron, dt: DateTime, kind: FieldKind, value: int): DateTime =
  let values = newTable[FieldKind, int]()
  for i in FieldKind.low.ord .. FieldKind.high.ord:
    let field = cron.fields[FieldKind(i)]
    values[FieldKind(i)] = if i < kind.ord:
      field.getValue(dt)
    elif i > kind.ord:
      field.minValue(dt)
    else:
      value
  initDateTime(values)


proc incNext(cron: Cron, dt: DateTime, kind: var FieldKind): DateTime =
  let values = newTable[FieldKind, int]()
  var i = 0
  while i >= FieldKind.low.ord and i <= FieldKind.high.ord:
    let field = cron.fields[FieldKind(i)]
    if field.kind == fkDayOfWeek:
      if i == kind.ord:
        dec(kind)
        dec(i)
      else:
        inc(i)
      continue
    if i < kind.ord:
      values[field.kind] = field.getValue(dt)
      inc(i)
    elif i > kind.ord:
      values[field.kind] = field.minValue(dt)
      inc(i)
    else:
      let value = field.getValue(dt)
      let maxVal = field.maxValue(dt)
      if value == maxVal:
        dec(kind)
        dec(i)
      else:
        values[field.kind] = value + 1
        inc(i)
  initDateTime(values)


proc getNext*(cron: Cron, dt: DateTime): Option[DateTime] =
  var next = dt.ceil
  var fk = 0

  while fk >= FieldKind.low.ord and fk <= FieldKind.high.ord:
    var fieldKind = FieldKind(fk)
    let field = cron.fields[fieldKind]
    var currentVal = field.getValue(next)
    var someNextVal = field.getNext(next)

    # Couldn't find next. Let's expand the search
    # to a higher resolution.
    if someNextVal.isNone:
      next = incNext(cron, next, fieldKind)
      fk = fieldKind.ord
      continue

    # Found the next time.
    # Let's narrow down the search.
    let nextVal = someNextVal.get
    if nextVal <= currentVal:
      inc(fk)
      continue

    # Can simply setNext for DayOfWeek.
    # Let's increment it.
    if fieldKind == fkDayOfWeek:
      next = incNext(cron, next, fieldKind)
      fk = fieldKind.ord
      continue

    # Set next with nextVal.
    next = setNext(cron, next, fieldKind, nextVal)
    inc(fk)

  some(next)


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
