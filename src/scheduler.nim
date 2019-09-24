type
  Beater* = ref object of RootObj ## Beater generates beats for the next runs.

  Runner* = ref object of RootObj ## Runner runs the tasks.

  Storage* = ref object of RootObj ## Storage stores tasks definitions.

  Scheduler* = ref object of RootObj ## Scheduler acts as an event loop and schedules all the tasks.

proc next*(beater: Beater): float = 0.0


type
  Cron* = ref object of Beater

type
  Interval* = ref object of Beater
