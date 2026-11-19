# Live Updates

The Android app ([android_app.md](android_app.md)) and the DM's Encounter page are told when something changes instead of asking the server over and over. Player web pages (sheets, the encounter page in a player's browser) do not use this; they work as before.

## How it works

- **Server → listeners.** Each phone (while the app is on screen) and the DM's Encounter page hold one open connection (Server-Sent Events): `GET /api/events` for the app, `GET /encounter/events` for the DM (DM only). Whenever something changes in the game, the server sends `changed` down every connection; each listener then fetches what it shows. Several changes close together become one notice.
- **What counts as a change:** every POST that succeeds — the web app changes the game only through POSTs (a player's request or answer, the DM's approval, a roll, Confirm, a commit, a device assigned to another Character, the turn advancing…).
- **DM's page → server.** An open builder sends its state only when it changes (a step picked, a Change, Roll All, Confirm); the page compares it locally a few times a second. When it hears `changed`, it fetches the answers and Rolls of each open builder (`GET /encounter/live/:id`) and refreshes the Player actions panel.
- **Fallback.** Every listener still refreshes by itself every 30 seconds, in case a connection dropped. A dropped connection is reopened by itself (the app waits 1, 2, 4 … up to 15 seconds between tries; the browser after 3 seconds) and refreshes when it reconnects. While the app has no live connection (e.g. an older server), it polls at its old pace: Initiative every 2 seconds, Sheet / Items / Scene every 5, Notes every 10.
- **Keeping connections healthy.** The server writes a heartbeat every 20 seconds and closes each connection after 10 minutes (the listener reconnects at once), so a phone that vanished does not hold a thread for long. The app closes its connection when it leaves the screen.

- **Stopping the server.** Ctrl-C closes every live connection first, so the server stops at once instead of waiting minutes for them (`ChangeFeed.close_on_signals!`, installed after the web server boots; the web server also gives open requests at most a second). A **second Ctrl-C** quits at once, whatever is still open. The phones and the DM's page reconnect by themselves when the server is back.

## Capacity

Each open connection holds one web-server thread. The table is planned for **8 players and the DM** (9 connections), plus the ordinary requests they make when they fetch; the server runs with up to **32 threads** (`set :server_settings` in `app.rb` for `ruby app.rb`; `config/puma.rb` for `puma` / `rackup`).

## Implementation

- `lib/change_feed.rb` — the version counter, the wait, and the event stream.
- `lib/routes/live_events.rb` — the `after` filter that counts a successful POST as a change, and the two event streams.
- `public/js/ui/dmNotices.js` — every DM page's `EventSource` (with the notice in the top bar); fires `live:changed` for `public/js/ui/liveSync.js` (builders: send state on change, fetch on `changed`) and `public/js/ui/flowsPanel.js`.
- `android/…/net/LiveEvents.kt` — the app's connection; `MainActivity` refreshes the screen, the assignment and the prompt badge on each notice.
