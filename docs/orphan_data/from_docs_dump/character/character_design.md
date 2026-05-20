# Character — Design

Character is a **coordinator**, not a calculator. It holds the small set of values that don't belong to a more specialized module (identity, base attributes, Tier Override, Ritual List) and routes every other read to the component that owns the answer. Keeping the surface narrow lets a future effects layer wrap reads uniformly: monkey-patch `Character#attribute` and every consumer sees the modified value.

## Key Operations

### Effective attribute composition

`attribute(key)` returns `base + Advancement#attribute_bonus(key) + Race#adjustment_for(key)` — three non-overlapping contributions summed. No clamping, no max enforcement, no formula. Components needing a special rule (caps at high tier, etc.) implement it themselves and return their adjusted contribution.

### Tier resolution

Tier Override **always wins**, even if Advancement was constructed without it — so an NPC with `tier: 3` in YAML stays tier 3 regardless of class levels. Derived values (`damage_resilience`, `max_hit_points`) read Tier back through Character, not Advancement directly, so the override stays authoritative through every consumer.

### Ability deduplication across Race and Advancement

`abilities` merges Race's and Advancement's lists keyed by name. **First seen wins** — Race iterates first, so a duplicate name from a class is suppressed in favor of the racial version. This prevents a doubled-scaling bug where the same scaling-ability name appears twice and each iteration adds the level. Today's assumption is that the same name from two sources is a config mistake; if combined scaling is ever wanted, the merge needs a redesign.

### Roster loading

`Character.load_yaml` reads a roster YAML and constructs a list of Characters. Notable side-effects:

- Advancement / skills / race configs are loaded **once** and shared across every Character — class definitions and racial rules are global.
- `total_class_levels` is computed up front and passed to `Race` so racial scaling abilities have the right total.
- A `tier:` override is forwarded to **both** Character and Advancement so either path returns the same answer.

Missing roster files return `[]` rather than raising — production starts empty until the DM drops a roster in. Missing config files default to empty hashes; derived bonuses collapse to 0 but the Character still loads.

### Tag normalization

The `tags` field defaults `['player_character']` when missing or empty. This default is the gateway to Tier auto-computation — without a matching tag in `tier_advancement`, Advancement falls back to the slowest progression.

## Responsibilities

### Owned

- Identity: `id`, `name`, `player`, `tags`, `ritual_list`.
- Base attribute storage and the `attribute_keys` constant.
- Holding one Race and one Advancement per Character.
- Tier Override (returned ahead of Advancement's computed Tier).
- Effective Attribute composition.
- Race/Advancement abilities merge with first-seen-wins.
- Roster YAML loading and wiring.

### Not owned

- **Tier auto-computation, attribute bonuses from levels, skill/save ranks, HP/mana formulas, damage_resilience class contribution** — Advancement.
- **Racial bonuses, abilities, speed, size** — Race.
- **Conditions, current HP, temp HP, magic toxicity, shock, active effects** — conditions.
- **Equipment, inventory, currency** — equipment.
- **Combat actions, attacks, dice rolls** — combat / dice resolution.

### Unassigned

- **Per-Character narrative state** (DM notes, custom flags). Conditions owns mechanical state but not narrative.
- **Cross-config validation** that `race:` and class keys exist in their configs (today they silently produce empty instances).
- **Persistence of identity mutations** (renames). Characters are read-only at startup.
