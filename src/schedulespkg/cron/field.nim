from strformat import fmt
from sequtils import map
from strutils import join
from options import Option, some, none
import times
import ./parser

type
  ExprKind* = enum
    ekAll # *
    ekAny # ?
    ekLast # L
    ekLastN # mL
    ekHash # H
    ekNum # m
    ekStep # m/n
    ekRange # m-n
    ekSeq # m,n,...
    ekIndex # m#n
    ekNearest # mW

  Expr* = ref object
    case kind*: ExprKind
    of ekNum:
      num*: int
    of ekStep:
      stepExpr*: Expr
      step*: int
    of ekRange:
      rangeSlice*: Slice[int]
    of ekSeq:
      exprs*: seq[Expr]
    of ekIndex:
      indexer*: int
      index*: int
    of ekNearest:
      nearest: int
    of ekLastN:
      last*: int
    else:
      discard

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

proc `$`*(expr: Expr): string

proc newAllExpr*(): Expr =
  Expr(kind: ekAll)

proc formatAllExpr(expr: Expr): string =
  "*"

proc newAnyExpr*(): Expr =
  Expr(kind: ekAny)

proc formatAnyExpr(expr: Expr): string =
  "?"

proc newLastExpr*(): Expr =
  Expr(kind: ekLast)

proc formatLastExpr(expr: Expr): string =
  "L"

proc newHashExpr*(): Expr =
  Expr(kind: ekHash)

proc formatHashExpr(expr: Expr): string =
  "H"

proc newNumExpr*(num: int): Expr =
  Expr(kind: ekNum, num: num)

proc formatNumExpr(expr: Expr): string =
  fmt"{expr.num}"

proc newStepExpr*(expr: Expr, step: int): Expr =
  Expr(kind: ekStep, stepExpr: expr, step: step)

proc formatStepExpr(expr: Expr): string =
  fmt"{expr.stepExpr}/{expr.step}"

proc newRangeExpr*(start: int, stop: int): Expr =
  Expr(kind: ekRange, rangeSlice: start .. stop)

proc formatRangeExpr(expr: Expr): string =
  fmt"{expr.rangeSlice.a}-{expr.rangeSlice.b}"

proc newSeqExpr*(exprs: seq[Expr]): Expr =
  Expr(kind: ekSeq, exprs: exprs)

proc formatSeqExpr(expr: Expr): string =
  expr.exprs.map(proc (x: Expr): string = fmt"{x}").join(",")

proc newIndexExpr*(indexer: int, index: int): Expr =
  Expr(kind: ekIndex, indexer: indexer, index: index)

proc formatIndexExpr(expr: Expr): string =
  fmt"{expr.indexer}#{expr.index}"

proc newNearestExpr*(nearest: int): Expr =
  Expr(kind: ekNearest, nearest: nearest)

proc formatNearestExpr(expr: Expr): string =
  fmt"{expr.nearest}W"

proc newLastNExpr*(last: int): Expr =
  Expr(kind: ekLastN, last: last)

proc formatLastNExpr(expr: Expr): string =
  fmt"{expr.last}L"

proc `$`*(expr: Expr): string =
  case expr.kind
  of ekAll: formatAllExpr(expr)
  of ekAny: formatAnyExpr(expr)
  of ekLast: formatLastExpr(expr)
  of ekHash: formatHashExpr(expr)
  of ekNum: formatNumExpr(expr)
  of ekStep: formatStepExpr(expr)
  of ekRange: formatRangeExpr(expr)
  of ekSeq: formatSeqExpr(expr)
  of ekIndex: formatIndexExpr(expr)
  of ekNearest: formatNearestExpr(expr)
  of ekLastN: formatLastNExpr(expr)

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
