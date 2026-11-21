# Device logs

The phones send their debug log, and screenshots taken in the app, to the
server. The server saves them in `device-logs/` at the top of the repository,
so they can be committed and read alongside the code they came from.

## What is saved

Each upload is one file, `device-logs/<yyyymmdd-hhmmss>-<character>.log`
(`device-<id>` when the device has no Character yet). A screenshot is saved
next to it as the same name with `.png`.

The top of every `.log` is a header written by the server:

| Line          | From                                                         |
|---------------|--------------------------------------------------------------|
| Kind          | `log` or `screenshot`                                        |
| Received      | the server's clock                                           |
| Character     | the Character the DM assigned to the device                  |
| Device id     | the device's id (its cookie, as on the Status page)          |
| IP            | the address the upload came from                             |
| User agent    | the app's HTTP client                                        |
| App version   | `BuildConfig.VERSION_NAME`, e.g. `v0.038 a (e687)` — the last part is the commit the APK was built from |
| Server commit | the server checkout's commit and branch, noting local changes |
| Device …      | what the app reports: manufacturer, model, Android version, screen, server address, VPN |
| Screenshot    | the `.png` saved with it, for a screenshot                   |

Then the app's whole debug log (capped at 2 MB, newest kept).

## How the phone sends

- **Settings → Send log to server** — the log.
- **A screenshot** taken while the app is on screen (Android 14 or newer,
  which tells the app; permission `DETECT_SCREEN_CAPTURE`, granted at
  install). The app copies its own window (`PixelCopy`) and sends it with the
  log; a toast says it was sent. Dialogs drawn in their own window and the
  system bars are not in the copy. Older Android does not report
  screenshots, so nothing is sent there.

The route is `POST /api/logs` (JSON: `log`, optional base64 `screenshot`,
`app.version`, `device`), answered with the saved file names. It works for an
unassigned device too.

## Branches

`device-logs/` belongs to the branch the logs were taken on. It is emptied
(all but `.gitkeep`) whenever a new branch is made and is never merged — see
[CLAUDE.md](../../CLAUDE.md).
