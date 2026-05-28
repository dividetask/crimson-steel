# Chronicle — Tests

Tests for the public entry points of the Chronicle domain.

Unless a test specifies otherwise, tests start from a baseline state with: `campaign_name = "Test Campaign"`, an arbitrary Timestamp, two Chapters (numbered 1 and 2), and no Entries.

---

## Read campaign metadata

**Get Campaign Name returns the stored value.** With state `campaign_name = "The Long Road"`: returns `"The Long Road"`.

**Set Campaign Name replaces the stored value.** Setting Campaign Name to `"A New Beginning"` makes subsequent Get Campaign Name calls return `"A New Beginning"`.

**Get current Timestamp returns the stored Timestamp.** With state `timestamp = {day_index: 100, round_of_day: 600}`: returns that pair verbatim.

---

## Advance time

**Adding rounds within a Day.** With `timestamp = {day_index: 5, round_of_day: 0}` and `rounds = 600`: the new stored Timestamp is `{day_index: 5, round_of_day: 600}`.

**Adding rounds that roll over.** With `timestamp = {day_index: 5, round_of_day: 14000}` and `rounds = 1000`: rolls over by one Day. New stored Timestamp = `{day_index: 6, round_of_day: 600}`.

**Adding days only.** With `timestamp = {day_index: 5, round_of_day: 600}` and `days = 3`: new stored Timestamp = `{day_index: 8, round_of_day: 600}`.

**Negative offsets work.** With `timestamp = {day_index: 5, round_of_day: 0}` and `rounds = -1`: rolls back into the previous Day. New stored Timestamp = `{day_index: 4, round_of_day: 14399}`.

---

## Manage Chapters

**List Chapters returns them in number order.** With Chapters `{number: 2, name: "B"}` and `{number: 1, name: "A"}` stored: returns `[{1, "A"}, {2, "B"}]`.

**Add Chapter inserts a new Chapter.** Calling Add Chapter with `number = 3, name = "C"`: subsequent List Chapters returns Chapter 3 alongside the existing ones.

**Rename Chapter changes the name only.** Renaming Chapter 1 from `"A"` to `"Beginnings"`: the Chapter's number stays 1, name is now `"Beginnings"`.

**Remove Chapter does not delete its Entries.** With Chapter 1 holding two Entries: removing Chapter 1 deletes the Chapter from the list but leaves both Entries intact, still tagged with `chapter = 1`. Subsequent List Entries returns those Entries; List Chapters omits Chapter 1.

---

## Manage Entries

**Add Entry assigns a unique ID.** Calling Add Entry with full Note fields: returns an integer ID. The next Add Entry returns a higher integer.

**Edit Entry updates only the supplied fields.** With an existing Note Entry having `title = "Old"` and `public_description = "Original body"`: editing with only `title = "New"` leaves `public_description` unchanged.

**Delete Entry removes by ID.** After Delete Entry on a known ID: subsequent Get Entry on that ID returns nothing.

**Get Entry returns full record.** Get Entry on a Creature Reference returns all shared fields plus `creature_id`, `creature_token`, and `tier`.

**Creature Reference with null tier defers to Creatures domain.** A Creature Reference with `tier = null`: callers reading the tier must look it up from the Creatures domain. With `tier` set explicitly, that value is used directly.

**Creature Reference title is typically blank.** Add Entry with `entry_type = "creature"` and `title = ""`: stored verbatim. The stub renders the creature's name without a suffix. With `title = "the Younger"`: the stub appends it to the creature name.

### List Entries filters

**No filters returns everything.** Calling List Entries with no parameters: returns every Entry in the Chronicle.

**Filter by chapter.** With Entries in Chapters 1 and 2: List Entries with `chapter = 1` returns only Chapter 1 Entries.

**Filter by entry_type.** With a mix of Notes and Creature References: List Entries with `entry_type = "note"` returns only Notes.

**Filter by active.** With some Entries active and others not: List Entries with `active_only = true` returns only the Active Entries.

**Combined filters are conjunctive.** List Entries with `chapter = 1, entry_type = "note", active_only = true`: returns Entries that are in Chapter 1 AND are Notes AND are Active.

**Visible-to filter respects Shared flag.** With one Shared Note and one unshared Note (`shared = false`): List Entries with `visible_to = some_creature_id` returns only the Shared Note.

**Visible-to filter respects hidden_from.** With a Public Note that has `hidden_from = [42]`: List Entries with `visible_to = 42` does not return that Note.

**Visible-to filter respects owner_id.** With a Note having `owner_id = 7` and `shared = false`: List Entries with `visible_to = 7` returns the Note. List Entries with `visible_to = 8` does not.

---

## Reorder Entries

**Set Notes Position inserts and shifts.** With three Notes in Chapter 1 having `notes_position` 1, 2, 3: setting the third Note's position to 1 shifts the others to 2 and 3. The new order is the moved Note first, then the originally-first Note, then the originally-second Note.

**Set Notes Position scopes by Chapter.** Notes in Chapter 1 don't shift when a Note in Chapter 2 has its `notes_position` set.

**Set Scene Position scopes across all Active Entries.** Active Entries have `scene_position` independent of their Chapter. Setting one Active Entry's `scene_position` shifts every other Active Entry's `scene_position`, regardless of which Chapter they're in.

**Position tie-break by storage order.** With two Entries that both report `notes_position = 5` (e.g., loaded from disk that way): the Entry stored first in the list is treated as appearing before the second when rendering. A subsequent reorder operation may resolve the tie by shifting one.

---

## Edge cases

**Add Entry to a non-existent Chapter is permitted.** Adding an Entry with `chapter = 99` when Chapter 99 doesn't exist: the Entry is created and stored. List Entries with `chapter = 99` returns it. List Chapters does not return Chapter 99.

**Get Entry on a deleted ID returns nothing.** After Delete Entry, the freed ID is not reused. Subsequent Add Entry calls assign higher IDs.

**hidden_from list with non-existent Creature IDs.** A Creature ID in `hidden_from` that doesn't reference any actual Creature: simply has no effect.

**Empty hidden_from is the default.** A Note with no `hidden_from` field set is treated as if `hidden_from = []`.

**Loaded Entry with missing notes_position.** When state is loaded from disk and an Entry has no `notes_position` field set: Chronicle assigns one — appending to the end of that Entry's Chapter.

**Loaded Entry with missing scene_position.** Same as above — appended to the end of the Active Entry list.
