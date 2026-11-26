@chapter 10 Time and the Calendar

# Timekeeping — Design

@player
Spells run out, poisons come due, wounds close, and shops restock — all on the clock. This chapter is how the table keeps that clock: the Round that every duration is counted in, and the calendar the campaign's days fall on.

@implementation
Owns calendar and clock calculations: translating timestamps into year/month/day/time-of-day, advancing time across Day and Round rollovers, and computing day-of-week. Pure calculation — Timekeeping holds no state. Callers pass a Timestamp in and receive derived values back.

## The Round

@player
The **Round** is the game's unit of time. One Round is {{Round Length}} seconds in the world.

Everything is counted in Rounds, however long it lasts. A fight is tracked Round by Round. Longer spans — a minute, an hour, a day — are each a fixed number of Rounds; the **Conditions** chapter's configuration table lists them under `Frequency Rounds`, because that is how often a slow poison or a disease comes due.

The **time of day** is simply how many Rounds have passed since midnight, at {{Round Length}} seconds each. When the count reaches a full day, it starts again from zero and the date moves on by one.

## The calendar

@player
A year has these **Months**, in order:

> {{Month Names}}

Their lengths in Days, in the same order:

> {{Month Lengths}}

The **week** runs through these Days and then starts over. It pays no attention to Months or years — the day after the last name is always the first name again:

> {{Day of Week Names}}

**Leap Years.** A year whose number divides evenly by {{Leap Year Interval}} is a Leap Year, and gains one extra Day in Month number {{Leap Month}}.

**Where the count starts.** The calendar is counted from the first Day of the first Month of the year {{Default Starting Year}}. That Day falls on the first name in the week above, and every other date follows from it. Dates before it work the same way, counting backwards.

## Keeping time at the table

@player
The DM is the timekeeper. The campaign has exactly one current date and time of day, recorded in the campaign's Chronicle (see the **Chronicle** chapter).

- **In a fight**, the clock moves by itself: each time a Round of combat is completed, add one Round.
- **Outside a fight**, the DM advances the clock by however long the party spends — some Rounds for a hurried search, hours for a march, days for a rest.
- **To advance by Rounds**, add them to the time of day. Each full day's worth of Rounds carries over as one Day on the date.
- **To advance by Days**, step the date forward, walking through the Month lengths above and rolling the year when the last Month ends.
- **To correct a mistake**, the clock can be moved backwards in exactly the same way.

Whenever the clock moves, check what was waiting on it:

- **Effects with a duration** end when their last Round has passed (see the **Conditions** chapter).
- **Afflictions** come due at their own frequency. If time jumps past several of an Affliction's intervals at once, it is owed one resolution for each interval missed — it does not skip to the present.
- **Natural Recovery** is counted in whole Recovery Ticks — one Day each in the tabletop game (see the **Conditions** chapter).

## What lives in the next chapter

@player
The next chapter, **The Map**, turns from *when* to *where*: the maps a scene is played on, the tokens that stand on them, and the areas that spells leave behind.

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
- Timekeeping does not know about Combat's Time Ticks, or any sub-Round subdivision. Domains that need finer granularity than a Round handle it themselves and pass whole-Round counts to Timekeeping.
- Configuration is loaded from `timekeeping_config.yaml` at boot.
