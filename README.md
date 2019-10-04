# nim-schedules

A Nim scheduler library that lets you kick off jobs at regular intervals.

## Getting Started

```bash
$ nimble install schedules
```

## Usage

```nim
import schedules, times, asyncdispatch

schedules:
  every(seconds=10, id="tick"):
    echo("tick", now())

  every(seconds=10, id="atick", async=true):
    echo("tick", now())
    await sleepAsync(3000)
```

1. Schedule thread proc every 10 seconds.
2. Schedule async proc every 10 seconds.

Note:

* Don't forget adding `--threads:on` when compiling your application.
* The library schedules all jobs at a regular interval, but it'll be impacted
  by your system load.

## Advance Usages

### Throttling

By default, only one instance of the job is to be scheduled at the same time.
If a job hasn't finished but the next run time has come, the next job will
not be scheduled.

You can allow more instances by specifying `throttle=`. For example:

```
import schedules, times, asyncdispatch, os

schedules:
  every(seconds=1, id="tick", throttle=2):
    echo("tick", now())
    sleep(2000)

  every(seconds=1, id="async tick", async=true, throttle=2):
    echo("async tick", now())
    await sleepAsync(4000)
```

## ChangeLog

Released:

* v0.1.0, [TBD](https://github.com/nim-lang/packages/pull/1196).

TODO:

* Support macro `cron()`.
* Support custom scheduler.
* Support setting `maxDue`.
* Provide HTTP control API.

## License

Nim-markdown is based on MIT license.
