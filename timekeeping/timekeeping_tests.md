# Timekeeping — Tests

Tests for the public entry points of the Timekeeping domain.

Unless a test specifies a different config, all tests use the values in `timekeeping_config.yaml`:
- Round Length: 6
- Default Starting Year: 4710
- Leap Year Interval: 4
- Leap Month: 2 (the 28-day month gains a 29th Day in Leap Years)
- Month Lengths: `[31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]`
- Month Names: 12 entries (Frosten through Longnight)
- Day of Week Names: 7 entries (Restday through Templeday)

Derived: Rounds Per Day = `floor(86400 / 6) = 14400`.

---

## Resolve a Calendar Date

**Day Index 0 is the first Day of the Default Starting Year.** Given `day_index = 0`: returns `{year: 4710, month: 1, day_of_month: 1, day_of_week: Restday}`.

**Day Index 1 advances the Day of Week.** Given `day_index = 1`: returns `{year: 4710, month: 1, day_of_month: 2, day_of_week: Toilday}`.

**Crossing a Month boundary.** Given `day_index = 31` (one full Frosten past Day Index 0): returns `{year: 4710, month: 2, day_of_month: 1, day_of_week: ...}`. The Day of Week is the entry at index `31 mod 7 = 3` (Marketday).

**A Leap Year extends the Leap Month.** Given `day_index = 789`: returns `{year: 4712, month: 2, day_of_month: 29, day_of_week: Feastday}`. Years 4710 and 4711 are non-Leap (365 Days each), so 4712 starts at `day_index = 730`; Brindle starts at `day_index = 761` and Brindle 29 lands on `day_index = 789`. The 29th of Brindle only exists because 4712 is a Leap Year (4712 mod 4 == 0).

**Year 4711 is not a Leap Year.** Given `day_index = 424` — the value a caller would compute assuming Brindle 29 of 4711 exists (365 + 31 + 28 = 424): returns `{year: 4711, month: 3, day_of_month: 1, day_of_week: Tradeday}`. Year 4711 is non-Leap, so Brindle has only 28 Days; the 29th calendar position past Frosten falls into Thawmoon 1 instead.

**Negative Day Index falls before the Default Starting Year.** Given `day_index = -1`: returns `{year: 4709, month: 12, day_of_month: 31, day_of_week: ...}`. The Day immediately before Day Index 0 is the last Day of the previous Year. Day of Week is `(-1) mod 7 = 6` (Templeday).

**Day Index spanning multiple years.** Given `day_index = 365`: returns `{year: 4711, month: 1, day_of_month: 1, day_of_week: ...}`. Year 4710 is not a Leap Year (4710 mod 4 ≠ 0), so it has 365 Days, and Day Index 365 is the first Day of 4711.

**Day Index spanning a Leap Year.** Given `day_index = 366` (one Day past the end of Year 4710): returns `{year: 4711, month: 1, day_of_month: 2, day_of_week: ...}`. Year 4710 was 365 Days; the extra Day comes from continuing into 4711.

---

## Resolve a Time of Day

**Round 0 is midnight.** Given `round_of_day = 0`: returns `"00:00:00"`.

**Round 600 is one hour later.** Given `round_of_day = 600` (with Round Length 6, that's 3600 seconds): returns `"01:00:00"`.

**Round 14399 is the last Round of the Day.** Given `round_of_day = 14399` (just before Day rollover): returns `"23:59:54"`. The final Round starts 6 seconds before midnight.

**Mid-day with non-zero minutes and seconds.** Given `round_of_day = 7250`: seconds elapsed = 43500. Returns `"12:05:00"`.

---

## Advance a Timestamp

**Adding Rounds within a Day.** Given `timestamp = {day_index: 100, round_of_day: 0}` and `rounds = 600`: returns `{day_index: 100, round_of_day: 600}`. No rollover.

**Rounds rolling over into a Day.** Given `timestamp = {day_index: 100, round_of_day: 14000}` and `rounds = 1000`: total Rounds = 15000. Carries one Day; new `round_of_day = 600`. Returns `{day_index: 101, round_of_day: 600}`.

**Multiple-Day rollover from Rounds.** Given `timestamp = {day_index: 0, round_of_day: 0}` and `rounds = 30000`: total Rounds = 30000. Two full Days plus 1200 Rounds. Returns `{day_index: 2, round_of_day: 1200}`.

**Adding Days only.** Given `timestamp = {day_index: 100, round_of_day: 5000}` and `days = 7`: returns `{day_index: 107, round_of_day: 5000}`. Round Of Day untouched.

**Adding both Rounds and Days.** Given `timestamp = {day_index: 50, round_of_day: 13000}`, `rounds = 2000`, and `days = 3`: Rounds total 15000 carrying one Day; combined Day delta is 4. Returns `{day_index: 54, round_of_day: 600}`.

**Subtracting Rounds across a Day boundary.** Given `timestamp = {day_index: 100, round_of_day: 100}` and `rounds = -200`: total Rounds = -100. Day carry is -1; new `round_of_day = 14300`. Returns `{day_index: 99, round_of_day: 14300}`.

**Subtracting Days.** Given `timestamp = {day_index: 5, round_of_day: 7000}` and `days = -10`: returns `{day_index: -5, round_of_day: 7000}`. Negative Day Index is valid.

---

## Edge cases

**Leap Year Interval of 0 disables Leap Years.** With config override `Leap Year Interval = 0`: Year 4712 is treated as a 365-Day Year. Brindle 29 of 4712 does not exist.

**Day Index covering exactly one cycle of Days of the Week.** Given `day_index = 7`: Day of Week wraps back to Restday.

**Day Index of 7 in a non-Leap context.** With the default config: returns `day_of_week = Restday`. The cycle is independent of Month boundaries.

**Sum of Month Lengths matches non-Leap Year length.** The default config sums to 365.
