type
  Beater = ref object of RootObj ## Beater generates beats for the next runs.

  Runner = ref object of RootObj ## Runner runs the tasks.

  Storage = ref object of RootObj ## Storage stores tasks definitions.

  Scheduler = ref object of RootObj ## Scheduler schedules the tasks.
