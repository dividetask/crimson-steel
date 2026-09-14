# Compendium

The Compendium is the in-app player handbook: every player and the DM use it to look up rules, terminology, and worked examples while playing. It lives at `/compendium` and is visible to DMs and players alike (see `menu_layout.md` for the access rules).

The Compendium is doc-driven. Every chapter on the page comes from a markdown file under `docs/common/` — no chapter content is hand-written into the Ruby side. Authors edit markdown; the app reads it; the page updates on reload.

It carries three bodies of content:

1. **The player's manual** — the player-facing half of each concept's design document, plus the Glossary, Spell list and Class list. Visible to everyone.
2. **Common Rules (DM)** — the *whole* design document for every concept under `docs/common/`, with its config table and canonical tests. DM-only.
3. **Website Design (DM)** — reference pages from `docs/website_design/` describing how this site implements the rules. DM-only.

## One document, two audiences

A concept's player prose and its implementer rules live in the **same file**, split by `@player` / `@implementation` markers. The file contract, the directives, and the authoring rules are defined once in [`../common/file_conventions.md`](../common/file_conventions.md) — that document is canonical; this one only describes what the page does with it.

The short version:

- `docs/common/<concept>/<concept>_design.md` holds both halves. A player sees the `@player` passages; the DM sees everything, with the player passages visually marked so the merged document can be reviewed at a glance.
- `@chapter <n> [title]` places the concept in the player's manual and names it there. No `@chapter` means the concept is DM-only.
- `{{Config Key}}` substitutes the live value from `<concept>_config.yaml`, so a worked example cannot drift from the value the code reads.

There is no "which document is canonical" rule any more, because there is only one document.

## Page layout

Two panes, mirroring the Status page convention: a ~180px left nav and a content pane. The selected entry is highlighted. Sub-views are addressed by `?view=<key>`; the global URL stays under `/compendium`, and the menu's `Compendium` link returns the viewer to the Glossary.

The left nav shows, in order:

1. **Chapter 1** — pinned above the Glossary (currently Magical Tier).
2. **Glossary** — the default landing pane.
3. **Spells** and **Classes**.
4. **The remaining chapters**, in `@chapter` order, each labelled with its number.

The DM additionally sees a **Common Rules (DM)** group and a **Website Design (DM)** group below the player entries.

When a sub-view contains a Mermaid diagram, the Mermaid renderer is loaded from a CDN. Pages without Mermaid blocks do not include the script.

### Chapter numbering and duplicates

Nav order comes from the `@chapter` directive, not from code. Nothing enforces uniqueness — if two concepts claim the same number, both render with a red duplicate badge in the nav and a flag on the Coverage page, so the clash is obvious on sight rather than silently resolved.

### View keys

| Key | View | Audience |
|---|---|---|
| `glossary` (default) | The merged Glossary | everyone |
| `spells`, `classes` | The Spell and Class lists | everyone |
| `<concept>` | That concept's chapter of the player's manual | everyone |
| `common` | The Common Rules coverage overview | DM |
| `common:<concept>` | That concept's full page | DM |
| a `DesignDocs` key | A website-design page | DM |

`?view=dice` and `?view=checks` still resolve, to `dice_resolution` and `check_resolution`, so links made before the concept folder became the key keep working.

A player who requests a DM-only key is treated as if the page did not exist and falls back to the Glossary, matching the rule in `menu_layout.md`. A DM viewing as a player is, for this purpose, a player.

## The Glossary view

The Glossary is the union of every glossary under `docs/common/`. The sources are **discovered, not registered**: `common_glossary.md` first (its definitions take precedence), then one group per concept folder carrying a `<concept>_glossary.md`. A glossary with no terms is silently skipped.

Within a source, each `## Heading` becomes a subsection and each `**Term**: definition.` paragraph a definition-list entry. Inline `code`, *italics*, and **bold** survive.

Term ownership is covered in [`../common/file_conventions.md`](../common/file_conventions.md).

## Common Rules (DM)

One nav entry per concept folder under `docs/common/`, plus a **Coverage** entry at the top of the group. Concepts are discovered by directory scan — `CommonDocs.concepts` — so there is no registry to update. `docs/common/ui/` is excluded: it holds this site's interface stubs rather than shared rules, and carries no concept file set.

Each concept page renders, in order:

1. A header line naming the chapter and linking to its player view (or noting that the concept is not in the book).
2. The **whole** design document, with `@player` passages wrapped in a marked block.
3. **Configuration** — the config table, every key including those marked `@dm`.
4. **Tests** — `<concept>_tests.md`, rendered as markdown. Never reaches a player.

A concept missing its design document renders an explicit gap rather than an empty page.

### Coverage

`?view=common` lists every concept against the four files it should carry, with each missing file called out. This is the review surface for the docs themselves: a concept that has drifted from the intended shape shows up as a row with holes in it, rather than as a page that quietly does not exist.

### Config tables

`<concept>_config.yaml` is rendered as a Setting / Value / Description table. Values come from the YAML; **descriptions come from the comments the file already carries**, so the table reads like the file and no description has to be maintained twice. The parsing rules (section dividers, which comment block belongs to which key, the `@dm` marker) are in [`../common/file_conventions.md`](../common/file_conventions.md).

Config keys default to player-visible — the values are the game's tunable rules and players need nearly all of them. A key marked `@dm` appears only on the DM page, badged.

## DM-only Website Design pages

Alongside the Common Rules, the Compendium surfaces reference pages drawn from `docs/website_design/`. These document *how the site implements the rules* — how a stub is defined, what it relies on, and the dummy data that drives it — so the DM can inspect and fix a feature while playing. They are **not** player content.

- **Registry.** Declared in `lib/design_docs.rb` (`DesignDocs::SOURCES`) as `{ key => { title:, path: } }`. Unlike the Common Rules, this registry stays **hand-curated**: `docs/website_design/` has no fixed per-folder file contract, so there is nothing to auto-discover, and the folder's `README.md` files are navigation for a repo reader rather than pages. The current entries are `combat`, `action_builder`, `combat_interfaces`, and `combat_test_data`.
- **Nav.** Rendered below the Common Rules group under a **Website Design (DM)** heading (`.compendium-nav-group`).
- **Access.** The standard `dm_view?` check, exactly as for the Common Rules.

These pages support the same `@function` and ` ```test ` stripping as the Common Rules, and render through the same `DocMarkdown` pipeline.

## Where the code lives

| Module | Responsibility |
|---|---|
| `lib/common_docs.rb` | Concept discovery, directive and marker parsing, `{{Config Key}}` substitution, per-audience rendering. |
| `lib/config_tables.rb` | `*_config.yaml` → table, including the comment-derived descriptions and `@dm` visibility. |
| `lib/doc_markdown.rb` | Shared kramdown + Mermaid rendering for every documentation surface. |
| `lib/glossary_docs.rb` | The merged Glossary. |
| `lib/design_docs.rb` | The hand-curated website-design pages. |
| `lib/routes/compendium.rb` | View-key resolution and access control. |
| `views/compendium.erb` | Nav groups and the content pane. |

## Authoring checklist

The per-file rules are in [`../common/file_conventions.md`](../common/file_conventions.md). For the page specifically:

1. A new concept folder needs no code change — it appears on the next reload.
2. A new chapter needs only an `@chapter` line in its design doc.
3. Check the Coverage page after adding a concept: an unexpected "missing" is either a file you still owe or a filename that does not match the convention.
4. Any Mermaid block should be confirmed in a browser — the CDN fails silently, so a broken diagram simply does not appear.
