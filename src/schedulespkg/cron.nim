# This is just an example to get you started. Users of your library will
# import this file by writing ``import scheduler/submodule``. Feel free to rename or
# remove this file altogether. You may create additional modules alongside
# this file as required.

from options import Option, some, none, get, isNone
import times

import ./expr
import ./parser
import ./field

#proc getNextValue*(field: Field, dt: DateTime): Option[int] =
  #let minVal = field.minValue(dt)
  #let maxVal = field.maxValue(dt)
  #let start = max(field.getValue(dt), minValue)
  #let next = start
  #if next <= maxVal:
    #result = some(next)
  #else:
    #result = none(int)

proc getNextForLastDayOfMonth*(field: Field, dt: DateTime): Option[int] =
  some(getDaysInMonth(dt.month, dt.year))

proc getNextForLastDayOfWeek*(field: Field, dt: DateTime): Option[int] =
  # TODO:
  # algorithm:
  #   get day of week for the last day in month
  #   -(7-n).
  none(int)

# TODO: rename index to nthdayofweek
proc getNextForIndex*(field: Field, dt: DateTime): Option[int] =
  var firstDayForIndex = field.expr.indexer - ord(getDayOfWeek(1, dt.month, dt.year))
  if firstDayForIndex <= 0:
    firstDayForIndex += 7

  let nextIndex = firstDayForIndex + (field.expr.index-1) * 7
  let daysInMonth = getDaysInMonth(dt.month, dt.year)

  if nextIndex <= daysInMonth and nextIndex >= dt.monthday:
    some(nextIndex)
  else:
    none(int)

proc getNextForRange*(field: Field, dt: DateTime): Option[int] =
  let fieldVal = field.getValue(dt)
  let fieldMin = max(field.minValue(dt), field.expr.rangeSlice.a)
  let fieldMax = min(field.maxValue(dt), field.expr.rangeSlice.b)

  let nextVal = max(fieldMin, fieldVal)

  if nextVal <= fieldMax:
    some(nextVal)
  else:
    none(int)

proc getNextForStepRange*(field: Field, dt: DateTime): Option[int] =
  let fieldVal = field.getValue(dt)
  let fieldMin = max(field.minValue(dt), field.expr.stepExpr.rangeSlice.a)
  let fieldMax = min(field.maxValue(dt), field.expr.stepExpr.rangeSlice.b)

  var nextVal = max(fieldMin, fieldVal)
  let offset = field.expr.step - (nextVal - fieldMin) mod field.expr.step
  nextVal += offset

  if nextVal <= fieldMax:
    some(nextVal)
  else:
    none(int)

proc getNextForAll*(field: Field, dt: DateTime): Option[int] =
  let fieldMin = field.minValue(dt)
  let fieldMax = field.maxValue(dt)
  let nextVal = max(field.getValue(dt), fieldMin)
  if nextVal <= fieldMax:
    some(nextVal)
  else:
    none(int)

proc getNextForStepAll*(field: Field, dt: DateTime): Option[int] =
  let fieldMin = field.minValue(dt)
  let fieldMax = field.maxValue(dt)
  var nextVal = max(field.getValue(dt), fieldMin)
  let offset = field.expr.step - (nextVal - fieldMin) mod field.expr.step
  nextVal += offset
  if nextVal <= fieldMax:
    some(nextVal)
  else:
    none(int)

# TODO: getNextForAny
# TODO: getNextForSeq
# TODO: getNextForHash
# TODO: getNextForNum
# TODO: getNextForNearest

when isMainModule:
  let dt = now()
  var f = Field(kind: fkDayOfMonth, expr: newLastExpr())
  echo f.getNextForLastDayOfMonth(dt).get
  f = Field(kind: fkDayOfWeek, expr: parseDayOfWeeks("4#3"))
  echo f.getNextForIndex(dt).get
  f = Field(kind: fkHour, expr: parseHours("23-23"))
  echo f.getNextForRange(dt).get
  f = Field(kind: fkMonth, expr: parseMonths("1-12/2"))
  echo f.getNextForStepRange(dt).get
  f = Field(kind: fkMonth, expr: parseMonths("*"))
  echo f.getNextForAll(dt).get
  f = Field(kind: fkMonth, expr: parseMonths("*/2"))
  echo f.getNextForStepAll(dt).get
