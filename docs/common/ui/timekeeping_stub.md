# Timekeeping Stub

A read-only display widget showing a Calendar Date, the Day of the Week, the Time of Day, and a visual representation of the Time of Day. Based on a Timestamp passed in by the application. The stub always renders the current in-game time — it does not have a "past" or "future" rendering mode.

See `ui_conventions.md` for shared rules.

## Layout

A rectangular banner. The sky fills the entire banner as a background; the date / day-of-week / time block overlays the top-left corner of the banner; the sun-or-moon icon traces a half-circle arc through the lower portion of the banner from the very left edge to the very right edge.

1. **Date overlay** (top-left) — three lines stacked:
   - Primary: the Day of Month, Month Name, and Year, larger and bolder.
   - Secondary: the Day of Week name.
   - Secondary: the Time of Day, rendered in a fixed-width font at the same size as the Day of Week line.
2. **Sky background** (fills the banner) — gradient (light blue by day, deep blue by night), a dashed horizon line along the bottom edge, a dashed half-circle arc spanning the lower portion of the banner left-to-right, and the sun-or-moon icon traversing that arc. Stars sprinkle the upper portion at night.

The banner is sized tall enough that the arc's apex (the icon at zenith) fits inside the stub with only a small headroom above it. The arc passes through the top-left region behind the date overlay; the overlay is opaque enough that this is not visually confusing.

The banner has no interactive elements. It is purely informational.

## Parameters

Required:
- A Timestamp — `(day_index, round_of_day)`.

The stub takes no display-format parameters; the Time of Day is always rendered as `HH:MM`, and whether it's day or night is communicated by the sky's sun-or-moon and background gradient.

## Date overlay

The overlay calls the Calendar Date entry point with the given `day_index` and the Time of Day entry point with the given `round_of_day`, then renders three lines in the top-left of the banner:

```
<day_of_month> <Month Name> <year>
<day_of_week>
<time_of_day>
```

The first line is the primary display (larger, bolder). The second and third lines are secondary (smaller, lighter) and share the same font size. The Day of Week is shown verbatim from the Calendar Date; the Time of Day is shown as `HH:MM` with the seconds component dropped. No AM/PM suffix is rendered because the sun-or-moon icon already conveys the half-day.

## Sky background

The Sky fills the banner. A dashed half-circle arc spans from the very left edge of the banner (sunrise / moonrise) to the very right edge of the banner (sunset / moonset). The sun-or-moon icon traces the arc so a viewer can estimate the Time of Day from the icon's height and horizontal position — directly overhead means midday for the sun and midnight for the moon; near the horizon means rising or setting.

Two daily halves drive the position:

- **Day half** — sun renders. Mapping: `06:00 → 0%` along the arc (eastern horizon), `12:00 → 50%` (zenith, top of arc), `18:00 → 100%` (western horizon).
- **Night half** — moon renders. Mapping: `18:00 → 0%`, `00:00 → 50%`, `06:00 → 100%`. The night fraction wraps midnight; implementations compute it as `(round_of_day − 0.75 × Rounds Per Day) / (0.5 × Rounds Per Day)` modulo 1.

The icon's coordinates along the arc follow the half-circle equation `y = baseline − sqrt(r² − (x − cx)²)` where `r` is the arc radius and `(cx, baseline)` is the arc's center on the horizon line. The arc itself is drawn as a faint dashed curve so the path is visible even when the icon is near the horizon.

The arc spans nearly the full height of the banner — the icon at zenith sits as high as it can go without clipping out the top of the stub, with only a few pixels of headroom above it. The arc is allowed to pass behind the date overlay in the top-left; the overlay is layered on top of the sky, and the path is what matters. The day half uses a light-blue sky gradient with a yellow sun and stylized rays. The night half uses a deep blue gradient with a moon (small shaded crescent) and a sprinkling of background stars in the upper-right area, away from the date overlay. The exact daytime/nighttime boundaries are 06:00–18:00; this could be configured per consuming project if needed.

A faint horizontal horizon line is drawn along the bottom edge of the banner to ground the arc.

## Interactive controls

The Timekeeping Stub itself has no interactive elements. Any DM-facing time-advance buttons that a consuming application wants (e.g. `+30 min`, `+1 hour`, `Next morning`) are page chrome, not part of this stub. A host page that wants to drive time forward places its own controls alongside the banner and POSTs to the Timekeeping entry point directly.
