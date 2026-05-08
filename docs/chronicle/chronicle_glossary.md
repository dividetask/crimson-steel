# Chronicle — Glossary

Defines the vocabulary used by `chronicle_design.md` and `chronicle_tests.md`. Chronicle holds the campaign's mutable state — notes, chapter structure, creature references, and the current Timestamp.

## Chronicle

**Chronicle**: The Campaign's mutable state — Campaign Name, current Timestamp, Chapter list, and Entry collection. Loaded from a data file at startup and persisted on every mutation.

## Campaign

**Campaign**: The current playthrough. Has a name and accumulates Chapters as it progresses.

**Campaign Name**: A human-readable label for the Campaign.

## Chapters

**Chapter**: A numbered narrative segment. Chapters are ordered by their number and used to group Entries.

## Entries

**Entry**: A single record in the Chronicle. Either a Note or a Creature Reference, distinguished by its Entry Type.

**Entry Type**: Either `note` or `creature`. Determines which type-specific fields apply.

**Note**: An Entry of type `note`. Used for narrative recaps, scene descriptions, encounter notes, and similar writing.

**Creature Reference**: An Entry of type `creature`. References a creature by its Creature ID. Chronicle-specific fields (descriptions, image, token, tier override) live on the Entry; the actual creature data lives in the Creatures domain.

## Visibility

**Public**: A boolean flag on an Entry. When true, players may see the Entry. When false, only the Game Master sees it.

**Hidden From**: A list of Creature IDs on an Entry. Even when an Entry is Public, players controlling any Creature in this list cannot see the Entry.

**Owner ID**: The Creature ID of the player creature that created this Entry, or null when the Entry was created by the Game Master. When set, the Entry is visible only to that owner (plus the Game Master).

**Active**: A boolean flag on an Entry. When true, the Entry is relevant to the current scene. The scene view shows only Active Entries; the notes view shows all Entries regardless.

## Position

**Notes Position**: An integer giving an Entry's order on the notes page within its Chapter. Always set; tie-breaker is the Entry's position in storage order (first encountered wins).

**Scene Position**: An integer giving an Entry's order on the scene page among Active Entries. Always set; same tie-breaker as Notes Position.
