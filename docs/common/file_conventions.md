# File Conventions

How the shared rules under `docs/common/` are organised, and what the website does
with each file. `domain_index.md` lists *which* concepts exist; this document
defines the *shape* every one of them takes.

These documents serve two readers at once:

- **Players**, who need to understand the rules well enough to play — and whose
  half of these documents is what gets printed as the player's manual.
- **Implementers** (a person or Claude), who need the rules precisely enough to
  write the code.

Those two readings must never disagree. That is the reason for the single-file
rule below: the player passage and the rule it describes live in the same file,
a few lines apart, so changing one without the other takes deliberate effort.

## The concept folder

Every concept gets one folder, `docs/common/<concept>/`, even when the concept
will not be a class in any particular project. The folder **is** the registry —
nothing is registered in code. A new folder appears on the Compendium as soon as
it exists, and a folder missing one of its files renders a visible gap rather
than silently not existing. That gap is the point: it is how a half-finished
concept shows up for review, on the Compendium's **Common Rules → Coverage**
page.

| File | Contains | Where it surfaces |
|---|---|---|
| `<concept>_design.md` | The rules. Player prose and implementer rules in one document, split by the visibility markers below. | The concept's page (DM, whole document) and its chapter of the player's manual (players, `@player` passages only). |
| `<concept>_config.yaml` | Tunable values. | A table on both the DM page and the player chapter. |
| `<concept>_glossary.md` | Terms this concept owns. | Merged into the Compendium Glossary. |
| `<concept>_tests.md` | Canonical test cases. | The end of the DM page. Never shown to players. |

Other `.yaml` files in the folder are **catalogs** (spell lists, loot tables,
creature data) rather than tunables. They are not rendered as config tables.

### Why the config lives in YAML

The config files exist so a value can be changed without touching a document or
a line of code. Most values have not been play-tested and will move repeatedly
during play-testing. Nothing that is expected to be retuned should be written as
a literal anywhere else — see **Config substitution** below.

## Directives

Directive lines are stripped from the rendered page but stay in the source file.

| Directive | Meaning |
|---|---|
| `@chapter <n> [title]` | This concept is chapter `<n>` of the player's manual, carrying `title` as its chapter name. Absent means the concept is not in the book. |
| `@player` | The content that follows is player-facing. |
| `@implementation` | The content that follows is implementer-only. `@dm` is accepted as a synonym. |
| `@function <name>` | A developer declaration. |
| ` ```test … ``` ` | A worked sample data blob or test cases. |

### Chapter numbers

The number lives in the design doc, and nothing enforces uniqueness — two
concepts may claim chapter 3. The website makes that obvious instead: both
chapters render with a red duplicate badge in the nav and a flag on the Coverage
page. Fix it by editing one of the two `@chapter` lines.

Chapter numbers belong **only** in `<concept>_design.md`. A `.yaml` file never
carries one.

### Visibility markers

A marker switches the visibility of everything after it. **Every heading resets
the visibility to `@implementation`**, so each section declares its own tracks
and an unclosed `@player` can never leak past the section that opened it.

```markdown
## Bonuses, Penalties, and the TN

@player
Bonuses *lower* the TN, Penalties *raise* it...

@implementation
Per-Type stacking: for each Bonus/Penalty Type, only the highest-positive...
```

The two defaults are deliberately opposite, because each is right for its medium:

> **Prose is implementer-first: players see only what is marked `@player`.**
> **Config is rule data: players see everything except keys marked `@dm`.**

Prose defaults hidden so the player's manual stays curated — a forgotten marker
costs a paragraph in the book, which is obvious when you read the chapter, and
never puts implementer notes in front of players. Config defaults visible
because nearly all of it is player knowledge (Die Size, Base Target Number,
Round Length, the Month names), and the exceptions are few enough to mark by
hand.

### Where a player section goes

As close to the rules it describes as the document structure allows — the
adjacency is the whole point. In a document whose implementer sections map
cleanly onto player concepts, interleave them as siblings
(`dice_resolution_design.md`). In a large reference-shaped document whose
structure does not map section-for-section, the player chapter runs first and
the implementer reference follows (`conditions_design.md`).

Either way the rendered chapter is contiguous — the book is assembled by
extracting the `@player` blocks in document order, so interleaving in the source
costs the reader nothing.

Never nest player content under an implementer-only heading. A player would then
see a heading written for implementers ("Common types", "Public entry points")
with the section's real content missing.

## Config substitution

Inside any document, `{{Config Key}}` renders the live value from the concept's
own `<concept>_config.yaml`, falling back to any other concept's config. An
integer offset is allowed — `{{Base Target Number - 1}}` — so a worked example
stays correct when the value is retuned. That is the only arithmetic supported;
this is not an expression language. An unknown key renders as a loud inline
marker rather than disappearing.

**Never write a config value as a literal.** This is the rule that keeps the
player's manual and the code in agreement through play-testing. Write the whole
worked example in terms of the config and it survives every retune:

```markdown
The Base TN is {{Base Target Number}} and the Minimum TN is {{Minimum Target Number}}.
You have a Skill Bonus of +{{Base Target Number - 1}}.

- The TN would drop from {{Base Target Number}} all the way to 1.
- That's {{Minimum Target Number - 1}} below the Minimum.
```

## Portability

`docs/common/` is shared with other projects built on the same rules — a
first-person-shooter variant is planned — so nothing here may assume this
website, this interface, or this campaign.

- **No routes, pages, or UI.** A common document never names `/compendium`, a
  left nav, a modal, or a button. Interface behaviour belongs in
  `docs/website_design/`.
- **Reference values by name.** `Base Target Number`, not `8`.
- **Campaign content is not a rule.** Monster stats, plot, and notes live in
  `data/`, not here.

`docs/common/ui/` predates this rule: it holds this site's interface stubs and
is **not** a concept folder — it carries no design/config/glossary/tests set and
gets no Common Rules page. It is a known exception awaiting a move to
`docs/website_design/`.

## Glossary and tests

**Glossary.** Every `<concept>_glossary.md` is discovered automatically; there
is no list to update. Within a file, each `## Heading` becomes a subsection and
each `**Term**: definition.` paragraph a definition-list entry. A glossary with
no terms is silently skipped, so an empty file costs nothing.

When a term is used in only one concept it stays in that concept's glossary.
When two or more use it, it moves to [common_glossary.md](common_glossary.md),
whose definitions take precedence; per-concept glossaries reference common terms
rather than redefine them.

**Tests.** `<concept>_tests.md` is implementer material and is never rendered to
a player. Numeric assertions belong here rather than in the prose.

## Authoring checklist

1. The folder carries all four files, or the Coverage page shows why not.
2. Every player passage is marked `@player`; everything else is left unmarked.
3. No config value is written as a literal — `{{Config Key}}` throughout.
4. The chapter renders with no `[unknown config key]` markers.
5. No player content sits under an implementer-only heading.
6. Nothing names a route, a page, or an interface element.
7. Every term used appears in this concept's glossary or in
   [common_glossary.md](common_glossary.md), or is defined inline at first use.
8. `@chapter` numbers are unique — the nav flags a clash in red.
