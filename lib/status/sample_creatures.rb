module Status
  # Sample Creatures for the Status > Creatures sub-view. The sub-view
  # renders each demo through both the Minimal Sheet stub and the Full
  # Sheet stub (see docs/common/ui/creatures_minimal_stub.md and
  # docs/common/ui/creatures_full_stub.md) so the layouts can be
  # compared side-by-side.
  #
  # The data shape mirrors what the live Creatures, Conditions,
  # Equipment, Abilities, and Proficiencies domains will eventually
  # produce when composed together. Until those domains land, the
  # values are hand-curated to match the reference screenshots
  # supplied with the design.
  #
  # Tier numbers track docs/common/ui/ui_conventions.md (Tier Color
  # mapping 0..5 → red/orange/yellow/green/blue/purple).
  module SampleCreatures
    module_function

    def demos
      [ash_windmere, bryn_ironvein, veyl_aetheris]
    end

    def by_index(i)
      demos[i]
    end

    # ---- 1. Ash Windmere — full Bard with spells, rituals, items, abilities

    def ash_windmere
      {
        id: 1,
        label: 'Ash Windmere — Tier 3 Bard with full kit',

        header: {
          name: 'Ash Windmere',
          player: 'Sam',
          summary: 'Human Bard 3',
          tier: 3,
          bab: 4
        },

        attributes: { str: 14, dex: 18, con: 16, int: 17, wis: 20, cha: 22 },

        vitals: {
          hp:   { current: 22, max: 48 },
          mana: { current: 9,  max: 31, regen: 3 },
          toxicity: { current: 0, threshold: 11 },
          temp_hp: 0,
          moderate_damage: 0,
          major_damage: 0,
          combat_pool: 5,
          damage_reduction: 0,
          damage_resilience: 3
        },

        initiative: { dice_count: 4 },
        perception: { dice: 6, bonus: 5 },
        speed: 30,

        actions: [
          { name: 'Rapier',        speed: 2, roll: '4d', attack_bonus: 3, dmg_bonus: 2, bleed: 1, mt: 8, notes: '' },
          { name: 'Hand Crossbow', speed: 3, roll: '3d', attack_bonus: 4, dmg_bonus: 1, bleed: 0, mt: 7, notes: '' },
          { name: 'Dodge',         speed: 0, roll: '3d', attack_bonus: 2, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],

        # Full-sheet Attributes table: one row per attribute with
        # Score, Half (modifier), Check (dice + bonus), Save (dice + bonus).
        attributes_table: [
          { attr: 'Strength',     score: 14, half: 7,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Dexterity',    score: 18, half: 9,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Constitution', score: 16, half: 8,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Intelligence', score: 17, half: 8,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Wisdom',       score: 20, half: 10, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Charisma',     score: 22, half: 11, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } }
        ],

        skills: [
          { name: 'Perform (Dance)', ranks: 5, dice: 8, bonus: 3 },
          { name: 'Persuasion',      ranks: 5, dice: 8, bonus: 3 },
          { name: 'Perception',      ranks: 5, dice: 7, bonus: 3 },
          { name: 'Arcana',          ranks: 5, dice: 7, bonus: 3 }
        ],

        items: {
          equipped: [
            { name: 'Rapier' },
            { name: 'Hand Crossbow' },
            { name: 'Studded Leather' }
          ],
          consumable: [
            { quantity: 2, name: 'Healing Draught' }
          ],
          ammunition: [
            { quantity: 20, name: 'Bolt' }
          ],
          other: [
            { quantity: 1, name: 'Lute' },
            { quantity: 5, name: 'Rations' },
            { quantity: 1, name: 'Bedroll' }
          ]
        },

        item_descriptions: [
          { name: 'Cloak of Resistance +1', description: 'Adds +1 to all saves; does not stack with other resistance items.' },
          { name: 'Lute of the Wandering Bard', description: 'Once per scene, grant Bardic Inspiration without spending the action.' }
        ],

        abilities: [
          { name: 'Bonus Feat',             description: 'Choose any 1st-level feat.' },
          { name: 'Magical Performance (3)', description: "Learn a magical variant of any Performance skill, used both for mundane checks and to create a magical performance. Maintaining a performance takes a main action each turn; bardic spells can be cast as part of that action. Only advances on bard levels." },
          { name: 'Bardic Spellcasting',    description: 'Cast a number of bardic spells as a main action while performing. Spells need not be prepared each day. Casting outside a performance takes twice as long.' },
          { name: 'Bardic Inspiration',     description: 'While performing, spend 1 mana (once per turn) to grant a pool of luck. Each point lets you or an ally reroll a single die before the initial check. Successes grant 1 luck (must be used before your next turn); a fumble awards luck to the DM instead.' },
          { name: 'Jack Of All Trades',     description: 'Treat all skills (except restricted skills) as trained, with effective ranks equal to half your level on checks where you have no ranks.' },
          { name: 'Better Lucky Than Good', description: 'Spend 3 mana during a round you cannot act (e.g. surprise round). Attacks against you (including spells) are made with half as many dice (min 3). Enemies are unconsciously aware of the penalty.' },
          { name: 'Performance Feat',       description: 'Gain Familiar, Social Spell, Spell Focus (Enchantment), or Spell Focus (Illusion) as a bonus feat.' },
          { name: 'Silver Tongue',          description: '+1 inherent bonus to Persuasion and Deception checks; applies when using versatile performance.' },
          { name: 'Unsettling Words',       description: 'Spend a luck point from your performance before an enemy rolls; pick one of their dice to reroll.' },
          { name: 'Versatile Performance', description: 'No description yet.' }
        ],

        spells: [
          { tier: 0, names: ['Mending'] },
          { tier: 1, names: ['Charm Person', 'Healing Word'] },
          { tier: 2, names: ['Suggestion'] }
        ],

        rituals: [
          { tier: 1, names: ['Comprehend Languages', 'Detect Magic'] }
        ],

        item_spells: [],

        active_effects: [],
        usable_spells:  [],

        notes: [
          { body: 'Placeholder note for the character.' }
        ]
      }
    end

    # ---- 2. Bryn Ironvein — minimal-sheet reference, martial Dwarf Fighter

    def bryn_ironvein
      {
        id: 2,
        label: 'Bryn Ironvein — Tier 1 Fighter, pure martial',

        header: {
          name: 'Bryn Ironvein',
          player: 'Mira',
          summary: 'Dwarf Fighter 3',
          tier: 1,
          bab: 5
        },

        attributes: { str: 19, dex: 11, con: 20, int: 10, wis: 13, cha: 7 },

        vitals: {
          hp:   { current: 0,  max: 20 },
          mana: { current: 8,  max: 8,  regen: 1 },
          toxicity: { current: 0, threshold: 7 },
          temp_hp: 0,
          moderate_damage: 0,
          major_damage: 0,
          combat_pool: 8,
          damage_reduction: 2,
          damage_resilience: 5
        },

        initiative: { dice_count: 6 },
        perception: { dice: 4, bonus: 2 },
        speed: 25,

        actions: [
          { name: 'Warhammer', speed: 3, roll: '6d', attack_bonus: 2,  dmg_bonus: 1, bleed: 0, mt: 7, notes: '' },
          { name: 'Dodge',     speed: 0, roll: '3d', attack_bonus: 0,  dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],

        attributes_table: [
          { attr: 'Strength',     score: 19, half: 9,  check: { dice: 4, bonus: 0 }, save: { dice: 4, bonus: 0 } },
          { attr: 'Dexterity',    score: 11, half: 5,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Constitution', score: 20, half: 10, check: { dice: 4, bonus: 0 }, save: { dice: 4, bonus: 0 } },
          { attr: 'Intelligence', score: 10, half: 5,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Wisdom',       score: 13, half: 6,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Charisma',     score: 7,  half: 3,  check: { dice: 3, bonus: 0 }, save: { dice: 3, bonus: 0 } }
        ],

        skills: [
          { name: 'Athletics',  ranks: 3, dice: 6, bonus: 1 },
          { name: 'Intimidate', ranks: 3, dice: 3, bonus: 0 },
          { name: 'Perception', ranks: 3, dice: 4, bonus: 2 }
        ],

        items: {
          equipped: [
            { name: 'Warhammer' },
            { name: 'Tower shield' },
            { name: 'Chain mail' }
          ],
          consumable: [
            { quantity: 1, name: 'Healing Draught' }
          ],
          ammunition: [],
          other: [
            { quantity: 3, name: 'Javelin' },
            { quantity: 1, name: 'Whetstone' },
            { quantity: 5, name: 'Rations' },
            { quantity: 28, name: 'Gold' }
          ]
        },

        item_descriptions: [],

        abilities: [
          { name: 'Darkvision',         description: 'See in dim light as if in bright light, and in darkness as if in dim light, out to 60 feet.' },
          { name: 'Dwarven Resilience', description: 'Advantage on saves against poison; resistance to poison damage.' },
          { name: 'Stonecunning',       description: 'Add proficiency to Intelligence (History) checks related to the origin of stonework.' },
          { name: 'Weapon Training',    description: 'Gain proficiency with all martial weapons.' },
          { name: 'Armor Training',     description: 'Gain proficiency with all armor and shields.' }
        ],

        spells: [],
        rituals: [],
        item_spells: [],
        active_effects: [],
        usable_spells: [],
        notes: []
      }
    end

    # ---- 3. Veyl Aetheris — Archetype demo, no Player line (DM-run)

    def veyl_aetheris
      {
        id: 9,
        label: 'Veyl Aetheris — Tier 2 Arcane Trickster (Archetype demo)',

        header: {
          name: 'Veyl Aetheris',
          player: nil,
          summary: 'High Elf Arcane Trickster 4',
          tier: 2,
          bab: 4
        },

        attributes: { str: 7, dex: 17, con: 11, int: 17, wis: 11, cha: 13 },

        vitals: {
          hp:   { current: 18, max: 22 },
          mana: { current: 12, max: 16, regen: 2 },
          toxicity: { current: 0, threshold: 7 },
          temp_hp: 0,
          moderate_damage: 0,
          major_damage: 0,
          combat_pool: 6,
          damage_reduction: 1,
          damage_resilience: 3
        },

        initiative: { dice_count: 5 },
        perception: { dice: 4, bonus: 0 },
        speed: 30,

        actions: [
          { name: 'Shortbow', speed: 2, roll: '4d', attack_bonus: 3, dmg_bonus: 0, bleed: 0, mt: 7, notes: '' },
          { name: 'Dagger',   speed: 1, roll: '3d', attack_bonus: 2, dmg_bonus: 0, bleed: 0, mt: 6, notes: 'Sneak Attack: +1d on flanked target' },
          { name: 'Dodge',    speed: 0, roll: '3d', attack_bonus: 1, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],

        attributes_table: [
          { attr: 'Strength',     score: 7,  half: 3, check: { dice: 3, bonus: 0 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Dexterity',    score: 17, half: 8, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Constitution', score: 11, half: 5, check: { dice: 3, bonus: 1 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Intelligence', score: 17, half: 8, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Wisdom',       score: 11, half: 5, check: { dice: 3, bonus: 1 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Charisma',     score: 13, half: 6, check: { dice: 3, bonus: 1 }, save: { dice: 3, bonus: 0 } }
        ],

        skills: [
          { name: 'Arcana',          ranks: 6, dice: 8, bonus: 2 },
          { name: 'Stealth',         ranks: 4, dice: 6, bonus: 2 },
          { name: 'Larceny',         ranks: 4, dice: 6, bonus: 2 },
          { name: 'Sleight of Hand', ranks: 4, dice: 6, bonus: 2 },
          { name: 'Game (Chess)',    ranks: 4, dice: 6, bonus: 2 }
        ],

        items: {
          equipped: [
            { name: 'Shortbow' },
            { name: 'Dagger' },
            { name: 'Studded Leather' }
          ],
          consumable: [],
          ammunition: [
            { quantity: 18, name: 'Arrow' }
          ],
          other: [
            { quantity: 1, name: 'Thieves Tools' },
            { quantity: 1, name: 'Component Pouch' }
          ]
        },

        item_descriptions: [],

        abilities: [
          { name: 'Low-Light Vision', description: 'See in dim light as if in bright light.' },
          { name: 'Keen Senses',      description: 'Trained in Perception.' },
          { name: 'Elven Magic',      description: 'Detect Magic at will.' },
          { name: 'Trapfinding',      description: 'Locate traps with a Perception check; disable them with Larceny.' },
          { name: 'Sneak Attack',     description: 'Bonus damage dice on flanked or unaware targets.' },
          { name: "Thieves' Cant",    description: 'A secret language used by rogues.' },
          { name: 'Arcane Spellcasting', description: 'Cast arcane spells using Intelligence.' },
          { name: 'Danger Sense',     description: 'Cannot be surprised while conscious.' },
          { name: 'Combat Trickery',  description: 'Make a Sleight of Hand check as part of an attack.' },
          { name: 'Mage Hand Legerdemain', description: 'Use Mage Hand to perform delicate sleight-of-hand at range.' },
          { name: 'Elemental Dart',   description: 'Spend mana to fire a dart of elemental energy.' }
        ],

        spells: [
          { tier: 0, names: ['Light', 'Message'] },
          { tier: 1, names: ['Fire Dart', 'Silent Portal'] },
          { tier: 2, names: ['Hideous Laughter'] }
        ],
        rituals: [],
        item_spells: [],
        active_effects: [
          { caster: 'Ash Windmere', source: 'Bardic Inspiration', rounds_left: 3 }
        ],
        usable_spells: [
          { name: 'Fire Dart', casting_time: '1 action', mana_cost: 1, save_tn: nil },
          { name: 'Silent Portal', casting_time: '1 action', mana_cost: 2, save_tn: 7 },
          { name: 'Hideous Laughter', casting_time: '1 action', mana_cost: 3, save_tn: 7 }
        ],
        notes: []
      }
    end
  end
end
