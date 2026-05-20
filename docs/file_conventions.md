# File Conventions

Each domain in this project is documented by a fixed set of files. This document defines what each file contains and the rules they follow. The conventions are domain-agnostic — they apply equally to dice resolution, check resolution, combat, character creation, etc.

## File set per domain

A domain named `<domain>` has these files:

| File | Purpose |
|---|---|
| `<domain>_glossary.md` | Defines the terms the domain uses. The vocabulary the design and tests files draw from. |
| `<domain>_design.md` | Describes how the domain works. Public entry points, operations, common types, rules. |
| `<domain>_config.yaml` | Tunable values for the domain (numeric thresholds, labels, etc.). |
| `<domain>_tests.md` | Defines the expected behavior of the public entry points as test cases. |
| `<domain>_data.example.json` | Starting-state seed data for state-storing domains. Loaded by the consuming project at startup in development mode. Calculation-only domains do not have this file. |
| `<entity>.yaml` (zero or more) | Reference catalog files alongside config. Used when a domain ships a sizeable list of entities (Skills, Items, Conditions, Damage Types, etc.) that callers consume as data. Filename matches the entity name in plural lowercase (e.g., `skills.yaml`); placed in the domain folder, not prefixed with the domain name. |

A domain may omit `<domain>_config.yaml` if it has no configurable values. A calculation-only domain (one that holds no state — e.g., Roll Resolution, Check Resolution, Timekeeping) does not have `<domain>_data.example.json`.

## Cross-file rules

- **Each term is defined in exactly one glossary.** The domain that owns the concept defines it. Other domains use the term without redefining it. If two domains both seem to need the term, identify which one *owns* it (where the rules about the term live) and define it there. If neither owns it, the term belongs in an upstream domain — possibly one not yet written, in which case it lives in `orphans.md` until that domain exists.
- **The glossary is the source of truth for vocabulary.** When a term is defined in the glossary, the design and tests files use that term consistently and don't redefine it. If a term needs more rigor than the glossary provides (e.g., "exact bit layout"), it gets a "common types" entry in the design file and the glossary entry references it.
- **The design is the source of truth for behavior.** Tests reference design entries by name. The design defines the contract; tests verify it.
- **The config is the source of truth for values.** The design and tests files refer to config keys by their human-readable name (`Base Target Number`, not `base_tn`). When a value appears in both the design and the config, the design describes its *role* and the config provides the *value*.
- **Function names are not part of the contract.** The design describes what a public entry point does; it does not name internal helpers. Implementers choose function names. Names referenced in design (e.g., `RAND_FULL_ROLL`) are conceptual labels for the entry point's role, not the literal symbol an implementation must use.
- **No file should contradict another.** If you find a contradiction, the design wins for behavior, the glossary wins for vocabulary, the config wins for values, and the tests reflect both.

## Within-file rules

### Glossary

- Each term is a heading or a bolded word followed by a definition.
- Definitions are concise — one or two sentences. If a term needs more, it likely belongs in the design file's "common types" instead.
- Glossary entries describe terms in domain language only. **No implementation details.** Field names (`casting_time`, `effect_hash`, etc.), specific YAML keys, function names, type signatures, schema layouts, default-value lists, and similar code-shaped references do not appear in the glossary. They belong in the design file's Common Types section. A glossary entry may say "the structure is defined in `<domain>_design.md`" but does not enumerate fields.
- `*(configurable)*` after a definition signals that the value lives in the domain's config file.
- `*(indirectly configurable)*` signals that the value is derived from other configurable values.
- The glossary is grouped into sections by topic. Section headings use `##`.

### Design

- Starts with a one-line summary of what the domain owns. If there's a sibling domain (e.g., dice resolution and check resolution), the summary names it and says what's in the other file.
- A `## Common types` section comes first. It defines structures and enums that multiple entries below will reference. Field names, types, defaults, and brief descriptions go here.
- A `## Public entry points` section defines what callers from other domains invoke. Each entry gives: input, behavior or pipeline, returns. Inputs and returns reference common types; pipelines name operations defined later.
- An `## Operations` section defines the building blocks the entry points compose. Each operation has clear rules, but doesn't repeat the I/O contract of the entry points that use it.
- The design avoids prescribing implementation. It describes *rules*, not *algorithms*. Where an algorithm is the rule (e.g., "the highest positive value per type wins"), state the rule, not the loop that computes it.

### Config

- YAML with comments above each value explaining what it controls.
- Keys are human-readable Title Case (`Base Target Number`, not `base_target_number`).
- The design and glossary refer to keys by exactly this name.

### Tests

- Tests are organized by public entry point. Each entry point has a section.
- Each test case has: a config block (or a reference to a default), inputs, and expected outputs.
- Tests describe externally observable behavior — what a caller sees. They don't probe internal helpers.
- Tests are normative. If the design and a test contradict, one of them is wrong and the contradiction must be resolved before either is considered correct.
- Tests are written as narrative scenarios — a bolded summary followed by setup, expected results, and any clarifying notes.

## When to add a new domain

A new domain warrants its own file set when:
- It has its own vocabulary that the existing domains don't share.
- Its rules can be described and tested without constant reference to another domain's rules.
- It has a clear set of public entry points that other domains call.

If those aren't true, the new behavior likely belongs inside an existing domain.

## Consuming project integration

This submodule lives inside a consuming project's `docs/` directory. The consuming project keeps a `data/` directory (gitignored) for two purposes: storing dynamic state, and overriding submodule values.

### Dev data

State-storing domains ship with a `<domain>_data.example.json` file in the submodule. The consuming project's loader reads this file at startup in development mode to seed the domain's state. The file uses JSON because state is record-shaped and emitted by the running app; YAML stays reserved for hand-edited config.

A consuming project's `data/` directory holds the domain's actual runtime state. Dev data is the *starting point* for development; it is not loaded in production and not affected by overrides.

### Config overrides

The consuming project may override values in any `<domain>_config.yaml` by placing override files in `data/`.

**Override file naming:**
- `data/overrides.yaml` — uses domain names as top-level keys.
- `data/overrides_<domain>*.yaml` — the file's contents are direct keys of that domain's config; no top-level domain key is needed or allowed.

**Examples:**

A single file overriding multiple domains:
```yaml
# data/overrides.yaml
dice_resolution:
  Die Size: 12

timekeeping:
  Default Starting Year: 1
```

A domain-specific file (the filename implies the domain):
```yaml
# data/overrides_dice_resolution.yaml
Die Size: 12
```

A homebrew-tagged file scoped to one domain:
```yaml
# data/overrides_dice_resolution_homebrew.yaml
Die Size: 12
```

**Loading rules:**
- The loader scans `data/` for any file matching `overrides*.yaml`.
- Files are merged in alphabetical order. When the same key appears in multiple files, the later file (alphabetically) wins.
- Scalar overrides replace the original. Lists replace the original entirely (no append behavior). Nested dictionaries merge recursively.
- A file named `overrides_<domain>*.yaml` must NOT include the domain name as a top-level key in its contents. Doing so is an error.

### What is overridden

Overrides apply only to `<domain>_config.yaml` files. They do not affect dev data files, design files, or anything else.

### Orphan data

When a creature sheet, stub, or other consumer needs *data* (not computation) that would belong to a domain we haven't designed yet, place it in an `orphan_data/` directory at the submodule root. One YAML file per future domain: `orphan_data/equipment.yaml`, `orphan_data/conditions.yaml`, `orphan_data/abilities.yaml`, etc.

Orphan data is pure data — anything computable from existing creature data does not go in orphan files. The rare exception is when a future domain will require pre-computed data as input rather than computing it on demand.

When the future domain is designed, its data migrates from `orphan_data/<future_domain>.yaml` into `<future_domain>_data.example.json` and the orphan file is deleted.
