# Timekeeping — Glossary

Defines the vocabulary used by `timekeeping_design.md` and `timekeeping_tests.md`. *(configurable)* values come from `timekeeping_config.yaml`.

Timekeeping is a pure-calculation domain. It holds no state — callers pass timestamps in and receive derived values back.

## Time Units

**Round**: The standard in-game time unit. Each Round represents a fixed real-world duration. *(configurable, default 6 seconds)*

**Day**: A calendar day.

**Year**: A calendar year.

**Month**: A named subdivision of a Year. Each Month has a configured length in Days and a name.

## Calendar

**Day of the Week**: A name attached to a Day, cycling through a configured sequence.

**Leap Year**: A Year with one extra Day inserted into a designated Month.

**Default Starting Year**: The Year corresponding to a Day Index of 0. Used as the campaign's calendar epoch. *(configurable)*

## Timestamps

**Day Index**: The number of Days elapsed since the start of the Default Starting Year.

**Round Of Day**: The number of Rounds elapsed since the current Day started.

**Time Of Day**: An hours-minutes-seconds representation of the current Round Of Day's position within a Day.
