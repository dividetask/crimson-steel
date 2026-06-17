module Combat
  # Self-contained test data for the combat encounter stub demo on /status.
  # Per docs/website_design/combat/test_data.md, the stub renders ONLY from
  # this blob — it never reads the data/ directory or any .example.* file.
  module SampleTurn
    module_function

    def blob
      {
        combatant: { name: 'Ash Windmere',
                     mana: { remaining: 9, max: 31 },
                     pool: { remaining: 5, max: 5 },
                     main_actions: 2,
                     incapacitated: false },

        config: { die_size: 10, base_target_number: 8, move_cost: 4 },

        targets: [
          { id: 303, name: 'Goblin Archer', side: 'enemy' },
          { id: 305, name: 'Cult Fanatic',  side: 'enemy' },
          { id: 109, name: 'Veyl Aetheris',  side: 'ally' }
        ],

        weapons: [
          { name: 'Longsword', kind: 'melee',  dice_cap: 7, speed: 2 },
          { name: 'Shortbow',  kind: 'ranged', dice_cap: 6, speed: 3 }
        ],

        defences: [
          { name: 'Dodge', kinds: %w[melee ranged spell], dice_cap: 5, speed: 0 },
          { name: 'Block', kinds: %w[melee ranged spell], dice_cap: 6, speed: 0 },
          { name: 'Parry', kinds: %w[melee],              dice_cap: 7, speed: 2 }
        ],

        spells: [
          { name: 'Elemental Dart', tier: 1, mana: 3, dice_cap: 6, skill: 'Evocation',
            targeting: 'single', resolution: 'attack' },
          { name: 'Bless',          tier: 1, mana: 3, dice_cap: 0, skill: 'Abjuration',
            targeting: 'self',   resolution: 'buff' },
          { name: 'Fireball',       tier: 2, mana: 6, dice_cap: 6, skill: 'Evocation',
            targeting: 'area',   resolution: 'save', save: 'Dexterity' },
          { name: 'Hold Person',    tier: 2, mana: 6, dice_cap: 6, skill: 'Enchantment',
            targeting: 'multi',  resolution: 'save', save: 'Wisdom' },
          { name: 'Chain Lightning', tier: 3, mana: 12, dice_cap: 7, skill: 'Evocation',
            targeting: 'multi',  resolution: 'save', save: 'Dexterity' }
        ],

        items: [
          { name: 'Potion of Heal Simple Wounds', qty: 2, target: 'self', resolution: 'utility' },
          { name: 'Scroll of Fireball', qty: 1, targeting: 'area', resolution: 'save', skill: 'Evocation', dice_cap: 6 }
        ],

        specials: [
          { name: 'Bardic Inspiration', activation: 'main',  kind: 'channeled' },
          { name: 'Rage',               activation: 'bonus', kind: 'named' },
          { name: 'Turn Undead',        activation: 'main',  kind: 'other' }
        ],

        luck_sources: [
          { name: 'Lyra (Bardic Inspiration)' },
          { name: 'DM Luck' }
        ]
      }
    end
  end
end
