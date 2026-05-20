# Timekeeping — Design

Timekeeping is a small, owned-by-no-one-else module that holds the game clock. The core idea: a single Round counter doubles as "rounds since day started" so the time of day is always derivable without a second variable drifting from it.

## Why one Round counter

A naïve design would maintain two counters: `current_round` (cumulative since combat start, or some other anchor) and `current_day`. Those two can drift if anything advances one without the other. Replacing both with a single "rounds-since-day-started" Round counter eliminates the drift class:

- Time of day = `round * round_length_seconds` → trivially correct.
- Day = the existing Day counter, only ever advanced as a side effect of Round wrap.
- "Round" still has a useful out-of-combat meaning (rounds-into-this-day) rather than being tied to combat lifecycle.

## State model

```
round          0..Rounds Per Day - 1  (rounds since current day started)
day            cumulative              (days since Initial Day)
tick           0..ticks_per_round - 1  (in-combat only; resets to 0 each Round)
ticks_per_round  set during combat by Combat; absent otherwise
```

`Rounds Per Day = floor(86400 / Round Length Seconds)` — a derived constant computed at boot.

## Advance cascade

The fundamental operation is `advance_tick`, called by Combat once per completed Tick:

```
tick += 1
if tick >= ticks_per_round:
    tick = 0
    advance_round
```

`advance_round` does the Round bump and the Day rollover:

```
round += 1
if round >= Rounds Per Day:
    round -= Rounds Per Day
    day += 1
```

(The subtraction keeps `round` in the valid range even if the caller stacks multiple advances faster than the cascade can catch up.)

`advance_time(rounds: N)` is the out-of-combat entry point — it advances Round by N, with Day rollovers, **without** touching Tick. Refuses to run while a combat is active to avoid two callers stomping on the round counter.

## Combat handshake

Combat is the only module today that drives `advance_tick`. The handshake:

1. **Combat start.** Combat computes `max(Turns Per Round[tier])` across present Combatants and calls `start_combat(ticks_per_round)`. Timekeeping sets the divisor and resets Tick to 0.
2. **Each Tick advance.** When a Tick completes (every Acting Combatant has resolved their turn), Combat calls `advance_tick`. Timekeeping handles the rollovers.
3. **Combat end.** Combat calls `end_combat`. Timekeeping clears the divisor and resets Tick to 0. Round and Day continue from whatever they were — combat doesn't unwind the in-game time.

## Persistence

The state file `data/timekeeping.yaml` is rewritten on every mutation (matching the Combat persistence pattern). Boot reads the file, falling back to `round = 0`, `day = Initial Day`, `tick = 0`, `ticks_per_round = nil` when missing.

## Module Scope

### Owned

- The four state values (round, day, tick, ticks_per_round).
- Boot config: Round Length Seconds, Initial Day.
- Rollover arithmetic across Tick → Round → Day.
- Time of Day derivation.
- State file persistence.

### Not owned

- The mapping from Tier to Turns Per Round (Combat).
- Per-Combatant Tick Schedule (Combat).
- The semantics of "what counts as a Tick complete" (Combat decides when to call `advance_tick`).
- Calendar features beyond Day (months, years, named seasons) — deferred until needed.

### Unassigned

- A configurable `Initial Round` (start the campaign at a specific time of day) — currently every campaign starts at midnight (`round = 0`).
- Calendar arithmetic (named months, leap rules, etc.).
- An event scheduling API ("fire callback at Day N, Round R") — today's consumers poll `current_round` / `current_day` as they need to.
