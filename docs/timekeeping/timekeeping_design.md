# Timekeeping — Design

Owns calendar and clock calculations: translating timestamps into year/month/day/time-of-day, advancing time across Day and Round rollovers, and computing day-of-week. Pure calculation — Timekeeping holds no state. Callers pass a Timestamp in and receive derived values back.

## Common types

### Timestamp

The pair callers pass to Timekeeping when they need derived values:

| Field | Type | Description |
|---|---|---|
| `day_index` | signed integer | Days elapsed since the start of the Default Starting Year. Zero is the first Day of the Default Starting Year. Negative values represent earlier Days. |
| `round_of_day` | integer in `[0, Rounds Per Day)` | Rounds elapsed since the current Day started. |

### Calendar Date

The structured form derived from a `day_index`:

| Field | Type | Description |
|---|---|---|
| `year` | signed integer | Calendar year. |
| `month` | integer in `[1, len(Month Names)]` | 1-indexed Month number. |
| `day_of_month` | integer in `[1, length of this Month]` | 1-indexed Day within the Month. |
| `day_of_week` | string | The Day's Day-of-Week name. |

## Public entry points

### Resolve a Calendar Date

Pure conversion. Translates a `day_index` into a Calendar Date.

Input: `day_index` — signed integer.

Returns: a Calendar Date.

Algorithm: walk Years (forward for non-negative `day_index`, backward for negative) consuming Days Per Year at each step until the remainder fits within the current Year. Then walk Months consuming Month lengths until the remainder fits within the current Month. Day of Week = `day_index mod len(Day of Week Names)`, with index 0 being the first entry; the result is wrapped to be non-negative for negative `day_index`.

Leap Years insert one extra Day into the configured Leap Month. The Year is a Leap Year when `year mod Leap Year Interval == 0`.

### Resolve a Time of Day

Pure conversion. Translates a `round_of_day` into a `HH:MM:SS` string.

Input: `round_of_day` — integer in `[0, Rounds Per Day)`.

Returns: a string formatted `HH:MM:SS`, where seconds = `round_of_day * Round Length` and `HH`, `MM`, `SS` are zero-padded.

### Advance a Timestamp

Pure conversion. Adds a signed offset to a Timestamp and returns the new Timestamp with all rollovers applied.

Inputs:
- `timestamp` — a Timestamp.
- `rounds` — signed integer, default 0.
- `days` — signed integer, default 0.

Returns: a new Timestamp.

Pipeline:
1. Add `rounds` to `round_of_day`. Carry whole-Day overflow into a `day_carry` integer (positive or negative). After this step, `round_of_day` is in `[0, Rounds Per Day)`.
2. Add `days + day_carry` to `day_index`.

The function does not advance time by years, months, or any larger unit. Callers needing those should compute the equivalent Day count from the calendar configuration and pass it as `days`.

## Operations

### Determining whether a Year is a Leap Year

A Year is a Leap Year when `year mod Leap Year Interval == 0`. Negative years follow the same rule (e.g., year `-4` is a Leap Year when the interval is 4). When Leap Year Interval is 0, no Year is a Leap Year.

### Days Per Year

For a non-Leap Year: the sum of Month Lengths.

For a Leap Year: the sum of Month Lengths plus 1, with the extra Day inserted into the Leap Month (the Leap Month's effective length is one greater for that Year only).

### Rollover arithmetic

When adding Rounds to a Timestamp, the whole-Day carry is `floor(new_round_count / Rounds Per Day)` and the new `round_of_day` is `new_round_count mod Rounds Per Day`. Floor and modulo use mathematical (non-negative remainder) semantics so the rule works for negative inputs.

When adding Days to a Timestamp, no further carry is needed — `day_index` is unbounded.

## Cross-domain interactions

- Timekeeping does not own state. The current Timestamp is held by some caller; Timekeeping translates the values it receives.
- Timekeeping does not know about combat, ticks, or any sub-Round subdivision. Domains that need finer granularity than a Round handle it themselves and pass whole-Round counts to Timekeeping.
- Configuration is loaded from `timekeeping_config.yaml` at boot.
