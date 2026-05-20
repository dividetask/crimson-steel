# Chronicle — Glossary

Defines the vocabulary used by `chronicle_design.md` and `chronicle_tests.md`. Chronicle holds the campaign's mutable state — notes, chapter structure, creature references, and the current Timestamp.

## Chronicle

**Chronicle**: The Campaign's mutable state — Campaign Name, current Timestamp, Current Chapter, the Chapter sequence, and the collection of Entries. Persisted across sessions.

## Campaign

**Campaign**: The current playthrough. Has a name and accumulates Chapters as it progresses.

**Campaign Name**: A human-readable label for the Campaign.

## Chapters

**Chapter**: A numbered narrative segment. Chapters are ordered by their number and used to group Entries.

**Current Chapter**: The Chapter the campaign is presently in. Starts at 1 when a new Chronicle is created and advances as the story progresses. When a new Entry is created without an explicit Chapter, it lands in the Current Chapter. Existing Entries do not move when the Current Chapter changes — an Entry's Chapter is fixed at creation time.

## Entries

**Entry**: A single record in the Chronicle. Either a Note or a Creature Reference, distinguished by its Entry Type.

**Entry Type**: The kind of an Entry — a Note or a Creature Reference. Determines which type-specific fields apply.

**Note**: An Entry containing narrative writing — recaps, descriptions, encounter notes, and similar.

**Creature Reference**: An Entry that refers to a creature in the Creatures domain. Chronicle-specific information (descriptions, image, token, Tier Override) lives on the Entry; the canonical creature data lives in Creatures.

## Visibility

**Public**: A visibility marker on an Entry. When set, players may see the Entry; otherwise only the Game Master sees it.

**Hidden From**: A per-Entry list of Creatures from which the Entry is hidden. A player controlling any listed Creature cannot see the Entry even when it is Public.

**Owner**: The player Creature that created an Entry. When set, the Entry is visible only to that owner (plus the Game Master). Absent when the Entry was created by the Game Master.

**Scene**: The information that is currently relevant to what the players are doing. The Chronicle's scene view shows only the Entries that belong to the Scene; the notes view shows all Entries.

**Active**: A marker that places an Entry in the Scene. Inactive Entries are not part of the current Scene — they record events that have already happened or information not currently relevant.

## Position

**Notes Position**: An Entry's order on the notes page within its Chapter. Always set; tie-breaker is the Entry's position in storage order (first encountered wins).

**Scene Position**: An Entry's order on the scene page among Active Entries. Always set; same tie-breaker as Notes Position.
