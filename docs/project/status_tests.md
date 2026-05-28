# Status Page Test Rendering

The DM-only Status page (see `menu_layout.md`) renders the canonical `*_tests.md` files under `docs/common/` as scannable cards beneath their matching stubs. The renderer lives in `lib/test_docs.rb` and parses a deliberately narrow subset of markdown — authors write tests in the format described here so they render correctly on the page.

The three test files currently rendered:

| Status sub-view | Source file |
|---|---|
| Dice Resolution (`?view=dice`) | `docs/common/dice_resolution/dice_resolution_tests.md` |
| Check Resolution (`?view=check`) | `docs/common/check_resolution/check_resolution_tests.md` |
| Conditions (`?view=conditions`) | `docs/common/conditions/conditions_tests.md` |

## File shape

A test file is structured as:

```
# Title

Intro paragraph(s).

- Config bullet…
- Config bullet…

---

## Section heading

**Test title.** Body sentence. More body. `code` and *italic* and **bold** work.

- Bullet listing a derived value.
- Another bullet.

**Next test title.** …

---

## Next section heading

…
```

Rendering rules:

- **Everything before the first `## ` heading is skipped.** The H1, intro paragraph(s), and any config-bullet preamble do not appear in the rendered card stack.
- **`## Heading`** opens a new section. The heading text becomes the section's `<h3 class="test-section-h">` label.
- **`---`** flushes the current section. Any subsequent test paragraphs belong to no section until the next `## ` heading arrives.
- **`**Title.** Body…`** starts a test paragraph. Title and body are mandatory; bullets are optional. A blank line ends the paragraph.
- **`- bullet`** under a test becomes a `<li>` in that test's `<ul class="test-card-bullets">`. Lines that are neither bullets nor blank are folded into the body prose.

## Test paragraph anatomy

Every test renders as a `.test-card` with:

- A bold title in the project's blue accent color.
- A body paragraph immediately under the title.
- An optional bulleted list of derived values, observations, or boundary checks.

Titles should fit on one line and read like a hypothesis ("A Roll with no modifiers and middling dice", "Reroll count exceeds eligible dice"). The body states the inputs and the expected behavior. Bullets are for derived values that the reader can verify line-by-line — TN computation, DoIS components, intermediate states — and for boundary checks attached to the same scenario.

## Inline dice arrays

A bracketed list of integers in the test body or bullets renders as colored `.die` boxes:

```
dice that land as `[6, 6, 5, 1, 3, 7]`
```

Per-die coloring:

| Die value | Class | Color |
|---|---|---|
| 1 | `die fail` | red |
| The Die Size (10 by default) | `die crit` | blue |
| Any value ≥ the test's TN | `die success` | green |
| Anything else | `die neutral` | uncolored |

### What counts as a dice array

A "dice array" is the literal markdown pattern `[ N, N, N, … ]` where every comma-separated element is a positive integer ≥ 1 and ≤ Die Size. The regex requires **at least two elements** — a singleton like `[10]` is rendered as plain text rather than a die box. Arrays containing any non-integer element (tuples, strings, nulls) don't match the pattern and stay as plain text — this is what protects `bonus_penalty_list` examples like `[('A', +1)]` and `reroll_changes` examples like `[8, null, null, null]` from being misread.

### Per-test TN

The renderer extracts each test's effective TN from its body + bullets so dice color correctly across tests with different TNs. Precedence:

1. **`Clamped to N`** wins — when a test discusses TN clamping, the post-clamp value is the effective TN regardless of what the pre-clamp `TN = …` text says.
2. **`TN = … = N`** — the rightmost number on the right-hand side of a `TN =` equation.
3. **`TN N`** / **`at TN N`** / **`TN of N`** — bare mentions.
4. Fallback: the config's Base Target Number (6 by default).

The prefix-`(?<![A-Za-z])` on the `TN =` pattern means **`TN Net Modifier = …` does not trigger the TN extractor** — the Modifier sits between `TN` and `=`, so the regex doesn't match. Authors don't need to dance around the phrase.

### When to write the TN out explicitly

Mention the TN in the test's inputs whenever any of these are true:

- The test's behavior depends on a non-default TN.
- The test's behavior depends on the TN at all, and the dice array benefits from being colored correctly on the rendered card.
- Reading the test in isolation (on the Status page, with no surrounding context) would leave the TN ambiguous.

Otherwise the default Base Target Number is implied. Authors don't have to repeat it.

The phrasing is up to the author. All of these work and the renderer picks up the same value:

- `…and dice [6, 6, 5, 1, 3, 7] at TN 6.`
- `…with TN 6, dice [6, 6, 5, 1, 3, 7].`
- `- TN = 6 (Base, no modifiers).`

### "Resolve a Roll without a Target Number" sections

Section headings matching `/without\s+a\s+Target\s+Number/i` disable Success coloring for every test in that section. Dice in those tests still color 1s red and the Die Size blue, but no other die is treated as a Success — because there is no TN to compare against.

If an ordering-only / no-TN test ever needs to live outside such a section, the simplest move is to write its dice array without numbers in the Success range, or to wrap it in a section heading that matches the pattern.

## Per-file overrides

Some files disable TN-based coloring entirely because their `[a, b]`-style patterns aren't dice rolls:

| View key | TN coloring |
|---|---|
| `dice` | per-test, full |
| `check` | per-test, full |
| `conditions` | **disabled** — `[amount, tick_length]` Heal Rate pairs look like dice arrays to the regex but aren't |

The list lives in `TestDocs.render_for`. New views default to TN coloring on; opt out when the file uses bracketed integer lists for non-dice purposes.

## Inline formatting

Inside any test title, body, or bullet:

| Source | Renders as |
|---|---|
| `` `code` `` | `<code>` pill with subtle grey background |
| `*italic*` | `<em>` |
| `**bold**` | `<strong>` |
| `[N, N, …]` | colored `.die` boxes (per above) |
| anything else | escaped plain text |

Standard markdown links, images, and headings inside test paragraphs are **not** parsed — the renderer is deliberately limited.

## Authoring checklist

Before merging a new or edited test:

1. Each test starts with `**Title.**` and a sentence of body.
2. Dice arrays use literal integer lists; non-dice integer pairs (config rates, indices, etc.) avoid the bracket-with-commas pattern, or live in a file that opts out of TN coloring.
3. Any non-default or behavior-relevant TN is named explicitly in the body or a bullet.
4. Section headings match the section's content — in particular, the "without a Target Number" phrase only appears in genuinely no-TN sections.
5. The rendered card on the Status page colors dice the way the test text claims they behave.
