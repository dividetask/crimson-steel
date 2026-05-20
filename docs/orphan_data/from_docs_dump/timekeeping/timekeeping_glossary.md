# Timekeeping — Glossary

Timekeeping owns the project-wide time system: a single Round counter that doubles as rounds-since-day-started, a Day counter, the Tick subdivision used during combat, and combat-start/end notifications. Combat is the primary advancer; downtime and "advance time" operations also call in. *(configurable)* values come from `timekeeping_config.yaml`.

## Time Units

**Round**: The standard in-game time unit. Advancing a Round advances the time of day. Stored as **rounds since the current day started** (0 to `Rounds Per Day - 1`); when it would exceed `Rounds Per Day`, it wraps to 0 and Day increments.

**Tick**: A subdivision of a Round used during combat. Outside combat, no Tick exists — Round is the finest unit. Inside combat, a Round is divided into `Ticks Per Round` equal slices and combat advances time one Tick at a time.

**Ticks Per Round**: The active divisor during a combat. Set by Combat at combat start (= the highest `Turns Per Round[tier]` across present Combatants); cleared at combat end. When no combat is active, every advance moves a full Round.

**Day**: A cumulative day counter, incremented when the Round counter wraps past `Rounds Per Day`. Starts at `Initial Day` from config.

**Round Length Seconds**: Real-world seconds one in-game Round represents. *(configurable, default 6)*

**Rounds Per Day**: `floor(86400 / Round Length Seconds)` — a derived constant. With the default 6-second Round, 14400 Rounds make a Day.

**Time of Day**: `Round * Round Length Seconds` formatted as HH:MM:SS. Derived; not stored.

## Operations

**start_combat(ticks_per_round)**: Called by Combat at combat start. Sets the divisor and resets the Tick counter to 0.

**advance_tick**: Called by Combat after each Tick of combat completes. Increments the Tick counter; when it reaches Ticks Per Round, resets Tick to 0 and advances the Round (which may cascade into a Day rollover).

**end_combat**: Called by Combat when combat ends. Clears the Ticks Per Round divisor and resets Tick to 0.

**advance_time(rounds:)**: For out-of-combat time passage (rest, travel, downtime). Increments Round by N, with Day rollovers as needed. Refuses to run while a combat is active — combat must `end_combat` first.

**current_tick / current_round / current_day / current_time_of_day**: Read-only accessors any module may call.

## State

**Timekeeping State**: Persisted in `data/timekeeping.yaml`. Schema: `round`, `day`, `tick`, `ticks_per_round`. State persists across server restarts.

## Module Scope

Owns:
- Round, Day, Tick counters; Ticks Per Round divisor during combat.
- Round/Tick/Day rollover arithmetic.
- Time of Day derivation.
- Timekeeping state file persistence.

Does not:
- Schedule combat turns — Combat owns the per-Combatant `tick_schedule`.
- Track Tier, Combatants, or any per-creature state.
- Drive scheduled events directly — other modules read `current_round` / `current_day` as needed.
