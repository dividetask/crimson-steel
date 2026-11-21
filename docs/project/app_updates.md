# App Updates

The Android app ([android_app.md](android_app.md)) updates itself from the Crimson Steel server it is connected to, so every phone runs the same build as the server — whatever branch the server computer has checked out and pulled. The app never updates on its own: the player does it from **Settings → App updates**.

## How it works

- **First install:** a player opens the server's website in the phone's browser and goes to **Status**, which shows their Character, their device id and **Download the app** (`/api/app/apk`, the newest APK on the server). No git access is needed.
- The build automation commits each new APK to `android/versions/vMAJOR.MINOR.apk`. When the DM pulls on the server computer, the newest one comes down with it.
- The server reports the newest APK it has (`GET /api/app/latest` → `{ version: "v0.037", size, url }`) and serves the file (`GET /api/app/apk`). Any device may ask, assigned or not.
- **Settings → App updates** shows *This app: v0.036 a (…)* and *Server: v0.037 — a newer version*, with **Update to v0.037**. Tapping it downloads the APK from the server over the Wi-Fi and hands it to Android's installer (`PackageInstaller`), which shows its own confirmation: **Install**.
- The first time, Android asks to allow *Install unknown apps* for Crimson Steel; the app opens that screen. After allowing it, tap **Update** again.
- Settings, the remembered server and the phone's device id are kept: an update needs no reassigning.

When the server starts while the app code in its checkout is newer than its newest APK (the build automation has not committed the APK yet, or the build failed), it prints a **WARNING** in the console: the checkout's version (`versionBase` in `android/app/build.gradle`), the APK the phones will be offered meanwhile, and the last build commit. Once the build lands, a `git pull` is enough — the server looks at `android/versions/` on every request.

If the server's build is **older** than the app (e.g. the server is on an older branch), Settings says so and offers nothing: Android cannot install an older build over a newer one. Pull the server (or switch it to the newer branch) instead.

## Implementation

- `lib/app_release.rb` — finds the newest `android/versions/v*.apk`; the two routes are in `lib/routes/api.rb`.
- `android/…/net/AppUpdater.kt` — compares versions, downloads, and installs through a `PackageInstaller` session; `SettingsActivity` shows the section and receives the installer's answer (it may ask Android to show its confirmation).
- Permission: `REQUEST_INSTALL_PACKAGES`.
