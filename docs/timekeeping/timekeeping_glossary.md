# Timekeeping — Glossary

Defines the vocabulary used by `timekeeping_design.md` and `timekeeping_tests.md`. *(configurable)* values come from `timekeeping_config.yaml`.

Timekeeping is a pure-calculation domain. It holds no state — callers pass timestamps in and receive derived values back.

## Time Units

**Round**: The standard in-game time unit. Each Round represents a fixed real-world duration. *(configurable, default 6 seconds)*

**Day**: A calendar day. Composed of a fixed number of Rounds. The number is derived from Round Length and the assumption that a Day is 86,400 real-world seconds.

**Year**: A calendar year. Composed of a sequence of Months whose lengths are configured.

**Month**: A named subdivision of a Year. Each Month has a configured length in Days and a name.

## Calendar

**Day of the Week**: A name attached to a Day, cycling through a configured sequence. The cycle has no relationship to Months — it advances independently.

**Leap Year**: A Year with one extra Day inserted into a designated Month. Whether a Year is a Leap Year is determined by the Leap Year Interval — every Year whose number is divisible by the interval is a Leap Year.

**Default Starting Year**: The Year corresponding to a Day Index of 0. Used as the campaign's calendar epoch. *(configurable)*

## Timestamps

**Day Index**: A signed integer counting Days elapsed since the start of the Default Starting Year. Day Index 0 is the first Day of the Default Starting Year. Negative values represent Days before the Default Starting Year.

**Round Of Day**: An integer counting Rounds elapsed since the current Day started. Always non-negative and less than Rounds Per Day.

**Time Of Day**: A `HH:MM:SS` representation of the current Round Of Day's position within a Day.

## Derived Values

**Rounds Per Day**: `floor(86400 / Round Length)` — the number of Rounds in a Day. *(indirectly configurable)*

**Days Per Year**: The sum of Month lengths plus one if the Year is a Leap Year. *(indirectly configurable)*
