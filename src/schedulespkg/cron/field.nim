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
  of fkDayOfWeek:   1
  of fkHour:        0
  of fkMinute:      0
  of fkSecond:      0

proc maxValue*(field: Field, dt: DateTime): int =
  case field.kind
  of fkYear:        9999
  of fkMonth:       12
  of fkDayOfMonth:  getDaysInMonth(dt.month, dt.year)
  of fkDayOfWeek:   7
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
