# Creature names

Every spawned Creature gets a name no other Creature has, so the tracker,
the map and the phones never show two "Common Orc"s.

- The first spawn keeps the plain name: **Common Orc**.
- The second renames the first **Common Orc 1** and is **Common Orc 2**.
- After that each new one takes the lowest free number: with Common Orc 1,
  2, 4 and 5 left, the next is **Common Orc 3**.
- Every Creature counts, including ones from earlier fights that have not
  been deleted. Templates do not count and are never renamed.
- Only spawned Creatures are ever renamed. A player Character or named NPC
  with the same name keeps it; the spawn takes a number.
- A name typed when spawning (the name override) is numbered the same way.

Implementation: `Creatures::RandomEncounter.unique_spawn_name`
(lib/creatures/random_encounter.rb), used by every spawn path.
