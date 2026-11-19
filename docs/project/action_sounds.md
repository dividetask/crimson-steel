# Action Sounds

An Ability or Spell can have a sound. When a player **takes** that action on the Android app ([android_app.md](android_app.md)) — sends the request — an audio bar appears at the bottom of the screen, over every tab: **▶ Play** (or ✕ to dismiss). While it plays: **Pause** / **Resume**, **■ Stop**, and its progress. The bar goes away when the sound ends or is stopped. The sound is downloaded once through the app's own connection and played from the phone. Nobody else hears it through the app.

## Adding a sound

1. Put the mp3 in `public/sounds/`.
2. Add a line to `config/action_sounds.yml`: the action's name as the app lists it, then the file name:

   ```yaml
   Rage: RAGE_AGAIN.mp3
   Fireball: fireball.mp3
   ```

Names are matched ignoring case, spaces and punctuation, and an item that holds a Spell (a *Scroll of Fireball*, a *Potion of …*) plays that Spell's sound. The file is re-read when it changes: no server restart and no app update needed. An entry whose file is missing is ignored.

Today: **Rage** → `RAGE_AGAIN.mp3`; **Fireball** → `Fireball.mp3` (also for a Scroll of Fireball).

## Implementation

- `lib/action_sounds.rb` — the name → file table; `api_turn_options` adds `sound: "/sounds/<file>"` to a matching Ability, Spell or Item option.
- The server serves `public/sounds/` as static files.
- `android/…/ui/SoundPlayer.kt` — streams it with `MediaPlayer` from the server (one sound at a time).
