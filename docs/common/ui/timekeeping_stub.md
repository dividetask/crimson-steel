# Timekeeping Stub

A read-only display widget showing a Calendar Date, the Day of the Week, and a visual representation of the Time of Day. Based on a Timestamp passed in by the application.

See `ui_conventions.md` for shared rules.

## Layout

A horizontal banner with three regions, left to right:

1. **Date region** — the Day of Month, Month Name, and Year on one line, with the Day of Week on a second line below in smaller or lighter text.
2. **Sky region** — centered. A sun or moon icon representing the current Time of Day. The icon's horizontal position within this region tracks the Time of Day's progression through the Day, sliding from left edge (start of Day) to right edge (end of Day). Optional decorative stars or clouds may sit behind the icon.
3. **Time region** — right-aligned. The Time of Day formatted as `HH:MM:SS` by default, or as `H:MM AM` / `H:MM PM` when the 12-hour-format parameter is set (see Parameters below).

The banner has no interactive elements. It is purely informational.

## Parameters

Required:
- A Timestamp — `(day_index, round_of_day)`.

Optional:
- Highlight flag — boolean. When true, the banner renders in a highlighted style indicating "this is the current time" (versus a faded style indicating a past or future Day). Used when multiple Timekeeping Stubs are stacked to show a sequence of Days.
- Time format — `24h` (default) or `12h`. When `12h`, the Time region renders the Time of Day as `H:MM AM` or `H:MM PM` (no seconds component). When `24h`, the Time region renders as `HH:MM:SS`. This is a display preference only; the underlying Timestamp is unchanged.

## Date region

The Date region calls the Calendar Date entry point with the given `day_index` and renders the result on two lines:

```
<day_of_month> <Month Name> <year>
<day_of_week>
```

The first line is the primary display (larger, bolder). The second line is secondary (smaller, lighter) and shows the Day of Week name verbatim from the Calendar Date.

## Sky region

The Sky region renders a half-circle arc from the left horizon (sunrise / moonrise) to the right horizon (sunset / moonset). A sun or moon icon traces the arc so a viewer can estimate the Time of Day from the icon's height and horizontal position — directly overhead means midday for the sun and midnight for the moon; near the horizon means rising or setting.

Two daily halves drive the position:

- **Day half** — sun renders. Mapping: `06:00 → 0%` along the arc (eastern horizon), `12:00 → 50%` (zenith, top of arc), `18:00 → 100%` (western horizon).
- **Night half** — moon renders. Mapping: `18:00 → 0%`, `00:00 → 50%`, `06:00 → 100%`. The night fraction wraps midnight; implementations compute it as `(round_of_day − 0.75 × Rounds Per Day) / (0.5 × Rounds Per Day)` modulo 1.

The icon's coordinates along the arc follow the half-circle equation `y = baseline − sqrt(r² − (x − cx)²)` where `r` is the arc radius and `(cx, baseline)` is the arc's center on the horizon line. The arc itself is drawn as a faint dashed curve so the path is visible even when the icon is near the horizon.

The day half uses a bright sky background (light blue gradient) with a yellow sun and stylized rays. The night half uses a deep blue background with a moon (with a small shaded crescent) and a sprinkling of background stars. The exact daytime/nighttime boundaries are 06:00–18:00; this could be configured per consuming project if needed.

A faint horizontal horizon line is drawn at `y = baseline` to ground the arc.

## Time region

The Time region calls the Time of Day entry point with the given `round_of_day` and renders the result in a fixed-width font. Under the default `24h` format the rendering is `HH:MM:SS`. Under `12h` the rendering is `H:MM` followed by ` AM` or ` PM` based on whether the Time of Day falls in the first or second half of the Day (using the same daytime/nighttime boundaries that drive the Sky region).

A separate note on interactive controls: any DM-facing time-advance buttons that a consuming application wants (e.g. `+30 min`, `+1 hour`, `Next morning`) are page chrome, not part of this stub. The Timekeeping Stub has no interactive elements; a host page that wants to drive time forward places its own controls alongside the banner and POSTs to the Timekeeping entry point directly.

## Highlight styling

When the Highlight flag is true, the banner uses a brighter background and stronger text contrast. When false, it uses a muted/faded style. This convention exists so a stack of Timekeeping Stubs (e.g., yesterday / today / tomorrow) visually distinguishes the current Day from neighboring Days.

## Composition

Multiple Timekeeping Stubs may be stacked vertically to show a sequence of Days. The application sets the Highlight flag on the current Day's Stub and clears it on the others.
