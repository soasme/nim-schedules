from options import Option, some, none
import times
import ./expr
import ./parser

type
  FieldKind* = enum
    fkYear
    fkMonth
    fkDayOfMonth
    fkDayOfWeek
    fkHour
    fkMinute
    fkSecond

  Field* = ref object
    kind*: FieldKind
    expr*: Expr

proc minValue*(field: Field, dt: DateTime): int =
  case field.kind
  of fkYear:        1970
  of fkMonth:       1
  of fkDayOfMonth:  1
  of fkDayOfWeek:   0
  of fkHour:        0
  of fkMinute:      0
  of fkSecond:      0

proc maxValue*(field: Field, dt: DateTime): int =
  case field.kind
  of fkYear:        9999
  of fkMonth:       12
  of fkDayOfMonth:  getDaysInMonth(dt.month, dt.year)
  of fkDayOfWeek:   6
  of fkHour:        23
  of fkMinute:      59
  of fkSecond:      59

proc getValue*(field: Field, dt: DateTime): int =
  case field.kind
  of fkYear:        int(dt.year)
  of fkMonth:       int(dt.month)
  of fkDayOfMonth:  int(dt.monthday)
  of fkDayOfWeek:   int(dt.weekday)
  of fkHour:        int(dt.hour)
  of fkMinute:      int(dt.minute)
  of fkSecond:      int(dt.second)

proc getNextValue*(field: Field, dt: DateTime): Option[int] =
  none(int)

when isMainModule:
  let dt = now()
  var f = Field(kind: fkYear, expr: newAllExpr())
  echo f.getValue(dt)
  f = Field(kind: fkMonth, expr: newAllExpr())
  echo f.getValue(dt)
  f = Field(kind: fkDayOfMonth, expr: newAllExpr())
  echo f.getValue(dt)
  f = Field(kind: fkDayOfWeek, expr: newAllExpr())
  echo f.getValue(dt)
  f = Field(kind: fkHour, expr: newAllExpr())
  echo f.getValue(dt)
  f = Field(kind: fkMinute, expr: newAllExpr())
  echo f.getValue(dt)
  f = Field(kind: fkSecond, expr: newAllExpr())
  echo f.getValue(dt)
  f = Field(kind: fkDayOfMonth, expr: newAllExpr())
  echo f.maxValue(dt)
