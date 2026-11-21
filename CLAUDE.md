# CLAUDE.md — Project Guidelines for Crimson Steel DM Tools

## Project Overview

Crimson Steel DM Tools is a local server that allows other players to connect to in order to view their character sheets, game notes, inventory, items for sale, current statuses, and view information relevant to their current choices. It also allows the DM to manage this information, add monsters, manage combat, manage hit points, and other useful tools.

- **Common design documents** (`.md` files in `docs/common/`) — General, project-agnostic rules: dice/check resolution, shared UI conventions, glossary terms.
- **Project design documents** (`.md` files in `docs/project/`) — Crimson Steel–specific rules: menu layout, page access, server behavior, anything that customizes the common rules for this project.
- **Configuration templates** (`.yaml.example` files in `docs/`) — Contains default rule data, and example campaign data
- **Configuration files** (`.json` in `data/`) — Contains rule data, and campaign data

### Documentation precedence

When a rule in `docs/project/` conflicts with a rule in `docs/common/`, the `docs/project/` rule wins. Treat `docs/common/` as the default behavior and `docs/project/` as the Crimson Steel override.

### DM vs. player identification

The website identifies viewers by where their HTTP request originates:

- A request whose remote address is the same machine as the server (loopback addresses such as `127.0.0.1` and `::1`) is treated as the **DM**.
- Every other request — anyone connecting from another device on the LAN — is treated as a **player**.

There is no login, password, or account selection. Identity is purely based on whether the request comes from the server host. The DM may temporarily view the site as a player would (see `docs/project/menu_layout.md`); that toggle is a UI convenience and does not change the underlying identification rule.

## Critical Rules

### Do not loop on errors — stop and explain

- If an approach fails twice, stop immediately. Do not retry the same strategy.
- Explain what went wrong, what was attempted, and suggest alternatives — let me decide how to proceed.
- Do not silently retry file operations, compilations, or code execution hoping for a different result.
- If a tool call or code execution returns an error, analyze the error before taking any further action.
- When stuck on a problem, present the situation clearly rather than burning through tokens on repeated attempts.

### Ask questions often

- Ask questions often especially when there is ambiguity or you believe I have made a mistake
- Ask questions in plain chat text, not via the `AskUserQuestion` / multiple-choice prompt tool. Do not use that tool in this project — write the question(s) as normal prose and wait for a reply.

### Stop after asking questions

- Whenever you have a question, or multiple questions, stop immediatly after asking them.

### No filler text or comments

- Don't add text to the UI that tells the user what they already know or
  what happens anyway (e.g. "Sent to the DM, who resolves it." under every
  action). Every line on a screen must earn its space.
- Don't write code comments that only restate the code. Comment the why, a
  non-obvious rule, or a link to the design doc — nothing else.
- Keep chat messages and commit messages short and to the point.

### Design document conventions

- All formulas use `floor()` for division (round down) unless explicitly stated otherwise.
- Use "Wisdom save" and "Dexterity save" — never "will save" or "reflex save".
- Use "magic toxicity" — not "mana saturation".
- Tier 0 is treated as 0.5 in all formulas.
- Cross-reference between documents using relative markdown links: `[SPELLS.md](SPELLS.md)`.

### Android build versioning (`android/`)

The build automation (`build_branches.sh`) builds pushed `claude/*` branches
and commits each new APK as `android/versions/vMAJOR.MINOR.apk`, using the highest version already on the branch with the
minor bumped by one. Several commits can be pushed before the next build, so
the app's `versionName` has three parts, e.g. `v0.037 a (e687)`:

- **Number** (`v0.037`) — set by hand. The predicted APK filename: the highest
  `vMAJOR.MINOR.apk` in the versions folder on the current branch, with the
  minor + 1. Keep the same digit width as the existing files.
- **Letter** (`a`) — set by hand. `a` for the first commit after a new APK
  lands. Each further commit pushed before the next APK lands moves to `b`,
  `c`, …. When a new APK lands, the number goes up and the letter resets to
  `a`.
- **Commit** (`(e687)`) — added by Gradle at build time: the first 4
  characters of the commit the APK was built from, matching the build
  commit's `(from e687bc0)`. Never write it by hand — a commit can't contain
  its own hash.

Rules:

- To decide the number and letter: fetch the branch first, then check whether
  the build automation committed a new APK since the version was last
  changed. New APK → next number, `a`. No new APK → same number, next letter.
  A failed build produces no APK, so it does not reset the letter.
- `versionCode` is generated at build time from a timestamp
  (`(System.currentTimeMillis() / 60000).toInt()` — minutes since epoch). This
  ensures every build is always higher than the last, regardless of branch, so
  APKs from different `claude/*` branches can be installed over each other
  without uninstalling first. Never set `versionCode` by hand.
- Bump the number/letter on every commit that changes the app, and put the
  hand-set part at the end of the commit message, e.g.
  `Bigger aspect glyph tiles (v0.024 b)`.
- Enable `buildConfig = true` so the app can show `BuildConfig.VERSION_NAME`.

This repo's build file is Groovy (`android/app/build.gradle`); the same logic
is written there as `versionBase` + a `git rev-parse` commit hash. Kotlin DSL
form (adapted from audiobook-reader):

```kotlin
defaultConfig {
    // ...
    // versionCode: timestamp-based, always increasing across branches.
    // versionName: predicted APK filename (vMAJOR.MINOR.apk = newest committed
    // APK minor + 1), a per-commit letter (a, b, c… for each commit pushed
    // before a new APK lands; resets to 'a' once a new APK is built), and the
    // 4-char hash of the commit Gradle built from. The first two are set by
    // hand; the hash is added at build time because a commit can't contain
    // its own hash.
    versionCode = (System.currentTimeMillis() / 60000).toInt()
    val versionBase = "v0.037 a"
    val commitHash = try {
        val process = Runtime.getRuntime().exec(arrayOf("git", "rev-parse", "--short=4", "HEAD"))
        process.inputStream.bufferedReader().readText().trim().ifEmpty { "unknown" }
    } catch (_: Exception) { "unknown" }
    versionName = "$versionBase ($commitHash)"
}
```

### After pushing — read the build result (`android/`)

There is no Android SDK in the agent's environment, so the build automation
is the only compile check. It picks up the tip of a pushed `claude/*` branch
within 5–15 minutes (see below) and commits the result back onto the
**same branch**:

- `Build vX.XXX.apk (from <sha>)` — it compiled; that APK is `<sha>`.
- `Build failed, no APK change (from <sha>)` — it did **not** compile.

Older versions of the script prefix the message with `<app>/<branch>:`
(e.g. `Build audiobook-reader/claude/x: no APK change (from <sha>)`). Either
way, a build commit that names an APK version means it built; one that
doesn't means it failed.

After every push:

- How long to wait: the script checks each app on its own schedule. If any
  `claude/*` branch of the app has a commit made in the last hour (including
  the script's own build commits), the app is **active** and is checked every
  5 minutes. Otherwise it is **quiet** and checked every 15 minutes. It goes
  by commit time, not push time, and a push does not move the next check
  forward — so the first push after a quiet spell can wait up to 15 minutes
  before it is even picked up, plus the Gradle build time.
- Before pushing, look at the newest commit on any `claude/*` branch
  (usually yours, or the script's last build commit): within the last hour
  → first check-in ~5 minutes after the push; older → ~15 minutes. Schedule
  a one-shot check-in rather than polling with `sleep`.
- At each check-in, `git pull` and find the build commit whose
  `(from <sha>)` matches the commit you pushed. Read the result; never guess
  it.
  - **Built** → done.
  - **Failed** → read `android/build-logs/build.log` for the Gradle error, fix it, push, and check again.
  - **No build commit for your sha yet** → check again in ~5 minutes. Only
    the branch tip is built, so if you pushed again in the meantime, look for
    your newest sha instead.
  - **Still nothing ~25 minutes after the push** → the script may not be
    running. Stop and tell me rather than continuing to wait.
- Pulling the build commits is not enough — read them before pushing again.
  Don't stack new work on top of a build that failed.
- Never force-push a `claude/*` branch: the build commits and APKs live on
  it. Always pull before pushing.

### Tell me what to update: server, APK, or both

After every push (and in the final message of any task that changed code),
state plainly what I need to do to get the change, using one of:

- **APK only** — grab the newest APK; the server can keep running as is.
  The change touches only `android/`.
- **Server update** — pull the branch and restart the server (`ruby app.rb`).
  The change touches anything the running server loads: `app.rb`,
  `config.ru`, `lib/`, `views/`, `public/`, `Gemfile`/`Gemfile.lock` (also run
  `bundle install`), or the shape of the `data/` files. Say whether the
  **old APK still works** with the new server, or whether I must also
  install the new APK.
- **Both** — server update and the new APK, e.g. when the app calls a new or
  changed `/api` route. Say which to do first if the order matters
  (normally: server first, then APK).
- **Nothing to update** — docs, specs, or `CLAUDE.md` only.

Notes:

- Changes under `public/` (JS/CSS) only need a browser refresh, not a
  restart, but say "Server update" anyway so I pull them; mention that a
  refresh is enough.
- Server state held in memory (e.g. actions in progress) is lost on
  restart; warn me if a restart would drop something I'm likely mid-way
  through.
- Put the same line at the end of the commit message body, e.g.
  `Update: APK only` or `Update: server + APK`.

### Device logs (`device-logs/`)

The server saves the logs and screenshots the phones send into `device-logs/`
at the repo root (see [docs/project/device_logs.md](docs/project/device_logs.md)).
Each `.log` starts with a header: the device, the app version (with the APK's
commit) and the server's commit.

- Whenever a new branch is made, empty `device-logs/` (delete everything but
  `.gitkeep`) in the branch's first commit — the logs belong to the branch they
  were taken on.
- Never merge `device-logs/` into another branch: when merging, keep the
  target branch's `device-logs/` as it is.
- To read a log the user mentions: `git pull`, then look in `device-logs/`
  (newest file name first; names start with the date and time).

### Configuration file architecture

| File | Purpose | Scope |
|------|---------|-------|

## File Structure

```
```
