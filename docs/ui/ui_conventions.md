# UI Conventions

Rules and shared patterns for UI specifications in this folder. The folder contains two kinds of specs: **stubs** (interactive widgets) and **tooltips** (read-only informational popups). Each spec file describes one component built on top of a domain.

UI specs are an optional layer. Some implementations of a domain (e.g., a C# server with no frontend) will not use them. UI is documented separately so domain implementers can ignore it entirely.

## File naming

- Stub spec files end in `_stub.md`. Tooltip spec files end in `_tooltip.md`.
- Each filename starts with the domain name. Multiple specs of the same kind in the same domain are disambiguated by an optional suffix that begins with an underscore: `<domain>_stub.md` or `<domain>_<suffix>_stub.md`. Same rule for tooltips.
- A domain may have zero, one, or multiple specs of either kind.

## Shared rules

These apply to all UI specs regardless of kind.

### Dice highlighting

In any spec that displays dice values, individual dice are highlighted by category:

| Category | Color |
|---|---|
| Failure (value = 1) | red |
| Critical Success (value = Die Size) | blue |
| Success (value ≥ TN, not Critical) | green |
| Neutral Result | unhighlighted |

The categories are defined by the dice resolution domain. The colors are a UI convention.

### Modifier presentation

Bonuses display with a `+` prefix; Penalties display with a `-` prefix. The numeric magnitude follows. The label (the domain-supplied name of the source — e.g., "Bardic Inspiration") follows the magnitude, separated by a space.

### Per-step traces

Specs that show a Roll's evolution display each step in order: the initial roll, then any reroll result, then any nudge result. Steps that did not run are omitted entirely (no empty placeholder).

### Tier Colors

Creatures have a Tier from 0 through 5. UI specs that color content based on Tier use this mapping:

| Tier | Color |
|---|---|
| 0 | red |
| 1 | orange |
| 2 | yellow |
| 3 | blue |
| 4 | green |
| 5 | purple |

The exact shade is an implementation choice. The mapping itself is the convention.

## Stub rules

A stub is a reusable interactive widget. These rules apply to stubs only.

### Composition

A stub may render as either a standalone widget or as a row inside a parent stub's wrapper. Stubs that are composable expose a flag (such as a "wrapper" toggle) so a parent can suppress the stub's outer markup and stack multiple instances under shared headers.

### Manual override fields

When a stub displays a final result derived from dice (e.g., DoIS, Critical Count), it offers manual override input fields alongside the displayed result. The override is the user's authority — useful for unusual rulings, GM adjustments, or corrections.

### Cross-stub composition

Stubs may compose: a parent stub renders a wrapper and calls a child stub multiple times within it. The child stub is responsible for its inner markup; the parent owns the outer wrapper. When composing:

- The parent supplies a flag to the child to suppress the child's wrapper markup.
- The parent owns batched actions (e.g., a single Confirm button that resolves all child rolls at once); each child stub has a flag to suppress its own action button when embedded.
- Each child instance receives a unique identifier from the parent so child-specific events can be addressed correctly.

## Tooltip rules

A tooltip is a read-only informational popup, typically triggered by hover or focus. These rules apply to tooltips only.

### Read-only

Tooltips contain no action buttons, manual override inputs, or any other interactive element. Their purpose is to surface information that helps a user understand a value or computation without leaving the parent context.

### Composition

Tooltips may compose: a parent tooltip renders its own framing and embeds one or more child tooltips as blocks within. The child tooltip is responsible for its inner content; the parent owns any surrounding labels, headers, and result calculations. Each child tooltip should specify whether it can be composed and what content it produces when embedded.

### No trigger specification

A tooltip spec describes *what content to render*, not *what triggers it*. The application decides where the tooltip appears and how it's invoked.

## What UI specs do not do

- UI specs do not duplicate domain rules. A spec describes *what fields to display* and *how to lay them out*, not *what the values mean*. The meaning lives in the domain's design file.
- UI specs do not specify implementation framework. ERB, React components, native UI — the spec is framework-agnostic and any of these can implement it.
- UI specs do not manage state. State belongs to the application; UI components render based on data the application provides.
