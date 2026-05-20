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

**Day Index**: The number of Days elapsed since the start of the Default Starting Year. The first Day of the Default Starting Year has Day Index zero; Days before that are negative.

**Round Of Day**: The number of Rounds elapsed since the current Day started. Less than Rounds Per Day.

**Time Of Day**: An hours-minutes-seconds representation of the current Round Of Day's position within a Day.

## Derived Values

**Rounds Per Day**: The number of Rounds in a Day, derived by dividing the real-world seconds in a day (86,400) by the Round Length and rounding down. *(indirectly configurable)*

**Days Per Year**: The sum of Month lengths, plus one when the Year is a Leap Year. *(indirectly configurable)*
