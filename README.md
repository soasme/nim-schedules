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
  every(seconds=10):
    echo("tick", now())

  every(seconds=10, async=true):
    echo("tick", now())

  every(seconds=10, async=true, throttle=2):
    echo("tick", now())
    await sleepAsync(3000)
```

2. Schedule thread proc every 10 seconds.
1. Schedule async proc every 10 seconds.
3. Schedule async proc every 10 seconds, at a maximum jobs of 2.

## ChangeLog

Released:

* This project will be released before 8 Oct, 2019.

## License

Nim-markdown is based on MIT license.
