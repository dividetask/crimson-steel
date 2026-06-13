# Compendium

The Compendium is the player-facing rules browser. It renders the chapter
overviews under [`../game_rules`](../game_rules) and a shared Glossary.

## Page & route

- **Route:** `GET /compendium` (`lib/routes/compendium.rb`). The `view` query
  param selects what to show; an unknown or missing `view` falls back to the
  first chapter.
- **View:** `views/compendium.erb` — a two-column layout (left nav + content).
- **Layout:** the shared `views/layout.erb` menu. Adding the Compendium does
  not change the top menu.

## Navigation

The left nav is built by `CompendiumDocs.nav_items`. It lists **one entry per
chapter that has an overview** — a directory `game_rules/<chapter>/` containing
`<chapter>_overview.md` — title-cased from the directory name (`check_resolution`
→ "Check Resolution"). The **Glossary is pinned last**. The `common/` directory
is never a chapter. Drop a new `<chapter>/<chapter>_overview.md` in and it
appears in the nav automatically; remove it and the nav entry disappears.

## Overview markup

Overviews are Markdown (rendered via kramdown + GFM) plus a small markup layer,
all handled by `lib/compendium_docs.rb`:

| Markup | Meaning | Rendered as |
|---|---|---|
| `[[Term]]` / `[[Term\|shown]]` | A Glossary keyword. | The (shown) text with a click/hover definition popup. |
| `{{ expression }}` | A value or formula from the chapter's `<chapter>_config.yaml`. | See **Value & formula injection** below. |
| ` ```test … ``` ` | A worked test in YAML. | Skipped entirely; preserved in source. |

### Value & formula injection

`{{ expression }}` is resolved against the chapter config (`CompendiumDocs.resolve`):

1. Each `<Name>` is replaced: a **config scalar** by its value; a **config
   formula** (a value containing `<…>`) by its parenthesized expansion;
   anything that is **not a config key** is kept as a bare name — these are the
   runtime inputs (`Attribute`, `Prowess`, `Dice Modifier`, …).
2. If nothing symbolic remains, the arithmetic is evaluated to a single number
   (`+ - * / %`, parentheses; division and modulo **floor**).
3. Otherwise the simplified expression is shown as an inline `code.cr-formula`.

A `{{Name}}` is the reference `<Name>`; expressions may also write `<Name>`
explicitly and combine them with arithmetic. So `{{Die Size}}` → `10`,
`{{Maximum Dice Formula}}` → `10`, and `{{Dice Cap Formula}}` →
`6 + (((Attribute / 2) + Prowess) % 5)`. Config scalars
are **never** baked into a formula's source — they are filled in at render time,
so changing the config updates every page automatically.

### Keyword popups

Glossary entries come from [`../game_rules/common/glossary.md`](../game_rules/common/glossary.md)
(`**Term**: definition` lines under `## Category` headings). `[[Term]]` is
matched case-insensitively, with a crude plural fallback (`Checks` → `Check`).
An unknown term renders as plain text so a page never breaks.

A keyword renders as `span.cr-kw` wrapping a hidden `span.cr-kw-pop`. The popup
shows on hover and keyboard focus (CSS) and is click-toggled sticky via
`.cr-kw-open` (`public/compendium.js`) — the same interaction as the Character
Sheet attribute popup.

## Ruby classes / files

| File | Responsibility |
|---|---|
| `lib/compendium_docs.rb` | Chapter discovery, nav, config load, `{{…}}` resolution + arithmetic, `[[…]]` keyword popups, test-stripping, mermaid rewrite, Glossary parsing/rendering. |
| `lib/routes/compendium.rb` | The `GET /compendium` route. |
| `views/compendium.erb` | Page layout, nav, content, script includes. |
| `public/compendium.js` | Keyword popup click/keyboard toggling. |
| `public/style.css` | `.compendium-*`, `.explainer`, `.cr-kw*`, `.cr-formula`. |

## Rendering pipeline

`render_overview(chapter)`:

1. Read the overview Markdown.
2. Strip ` ```test ``` ` blocks.
3. Replace `[[…]]` and `{{…}}` with placeholder tokens (so kramdown can't mangle
   the injected HTML), recording each fragment.
4. Render Markdown → HTML (kramdown GFM).
5. Restore the tokens.
6. Rewrite ` ```mermaid ``` ` fences to `div.mermaid` (Mermaid script is loaded
   only when a page actually contains one).
