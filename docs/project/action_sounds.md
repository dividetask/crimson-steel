# Action Sounds

An Ability or Spell can have a sound. When a player picks that action on the Android app's Initiative screen ([android_app.md](android_app.md)), the action's card shows **▶ Play \<action\> sound**, which plays it on their own device (tap again — **■ Stop sound** — to stop it). Nobody else hears it through the app.

## Adding a sound

1. Put the mp3 in `public/sounds/`.
2. Add a line to `config/action_sounds.yml`: the action's name as the app lists it, then the file name:

   ```yaml
   Rage: RAGE_AGAIN.mp3
   Fireball: fireball.mp3
   ```

Names are matched ignoring case, spaces and punctuation. The file is re-read when it changes: no server restart and no app update needed. An entry whose file is missing is ignored.

Today: **Rage** → `RAGE_AGAIN.mp3`.

## Implementation

- `lib/action_sounds.rb` — the name → file table; `api_turn_options` adds `sound: "/sounds/<file>"` to a matching Ability, Spell or Item option.
- The server serves `public/sounds/` as static files.
- `android/…/ui/SoundPlayer.kt` — streams it with `MediaPlayer` from the server (one sound at a time).
