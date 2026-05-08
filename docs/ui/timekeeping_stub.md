# Timekeeping Stub

A read-only display widget showing a Calendar Date, the Day of the Week, and a visual representation of the Time of Day. Based on a Timestamp passed in by the application.

See `ui_conventions.md` for shared rules.

## Layout

A horizontal banner with three regions, left to right:

1. **Date region** — the Day of Month, Month Name, and Year on one line, with the Day of Week on a second line below in smaller or lighter text.
2. **Sky region** — centered. A sun or moon icon representing the current Time of Day. The icon's horizontal position within this region tracks the Time of Day's progression through the Day, sliding from left edge (start of Day) to right edge (end of Day). Optional decorative stars or clouds may sit behind the icon.
3. **Time region** — right-aligned. The Time of Day formatted as `HH:MM:SS`.

The banner has no interactive elements. It is purely informational.

## Parameters

Required:
- A Timestamp — `(day_index, round_of_day)`.

Optional:
- Highlight flag — boolean. When true, the banner renders in a highlighted style indicating "this is the current time" (versus a faded style indicating a past or future Day). Used when multiple Timekeeping Stubs are stacked to show a sequence of Days.

## Date region

The Date region calls the Calendar Date entry point with the given `day_index` and renders the result on two lines:

```
<day_of_month> <Month Name> <year>
<day_of_week>
```

The first line is the primary display (larger, bolder). The second line is secondary (smaller, lighter) and shows the Day of Week name verbatim from the Calendar Date.

## Sky region

The Sky region calls the Time of Day entry point and the Calendar Date entry point. It renders an icon and positions it horizontally within the region:

- A sun icon when the Time of Day falls within the daytime window.
- A moon icon when the Time of Day falls within the nighttime window.
- The icon's horizontal position is `round_of_day / Rounds Per Day` of the way across the region — left edge at start of Day, right edge at end of Day.

The exact daytime/nighttime boundaries are an implementation choice and may be exposed as a UI configuration option. A reasonable default is sun from 06:00:00 to 18:00:00 and moon otherwise.

A faint horizontal line beneath the icon reinforces the progression — left edge to right edge, with the icon as the marker.

## Time region

The Time region calls the Time of Day entry point with the given `round_of_day` and renders the result as `HH:MM:SS` in a fixed-width font.

## Highlight styling

When the Highlight flag is true, the banner uses a brighter background and stronger text contrast. When false, it uses a muted/faded style. This convention exists so a stack of Timekeeping Stubs (e.g., yesterday / today / tomorrow) visually distinguishes the current Day from neighboring Days.

## Composition

Multiple Timekeeping Stubs may be stacked vertically to show a sequence of Days. The application sets the Highlight flag on the current Day's Stub and clears it on the others.
