require_relative '../proficiencies'
require 'dice_resolution'

module Status
  # Sample Creatures for the Status > Creatures sub-view. Per the
  # project's per-page-data rule, this is hand-curated dummy data for
  # the Status page only — not a window into the live Creatures
  # roster. Used by /character-sheets too while live data wiring is
  # still pending the rest of the Creatures domain.
  #
  # What is hand-stored vs computed:
  #   - Stored: header / class entries (class key, level, trained
  #     skill keys, choices), Effective Attributes, vitals, actions,
  #     items, abilities, spells, rituals, notes.
  #   - Computed via the live class functions: Skill ranks
  #     (Proficiencies::Ranks.ranks_for_skill, which applies Skill
  #     Rate Resolution and the Proficiency Advancement Rates) and
  #     the resulting dice / bonus (Proficiencies skill prowess plus
  #     DiceResolution.translate_prowess).
  #
  # When the Creatures domain's vitals (HP / Mana / Effective
  # Attributes / etc.) come online they'll replace the stored values
  # in the same way the Skills section already does.
  module SampleCreatures
    module_function

    def demos
      [ash_windmere, bryn_ironvein, veyl_aetheris]
    end

    def by_index(i)
      demos[i]
    end

    # ---- 1. Ash Windmere ------------------------------------------------

    def ash_windmere
      attrs = { str: 14, dex: 18, con: 16, int: 17, wis: 20, cha: 22 }
      classes = [{ key: 'bard', level: 3,
                   trained_skills: %w[perform_dance persuasion perception arcana] }]
      base_data(
        id: 1,
        label: 'Ash Windmere — Tier 3 Bard with full kit',
        header: { name: 'Ash Windmere', player: 'Sam',
                  summary: 'Human Bard 3', tier: 3, bab: 4 },
        attributes: attrs,
        classes: classes,
        vitals: {
          hp:   { current: 22, max: 48 },
          mana: { current: 9,  max: 31, regen: 3 },
          toxicity: { current: 0, threshold: 11 },
          temp_hp: 0, moderate_damage: 0, major_damage: 0,
          combat_pool: 5, damage_reduction: 0, damage_resilience: 3
        },
        initiative: { dice_count: 4 },
        perception: { dice: 6, bonus: 5 },
        speed: 30,
        actions: [
          { name: 'Rapier',        speed: 2, roll: '4d', attack_bonus: 3, dmg_bonus: 2, bleed: 1, mt: 8, notes: '' },
          { name: 'Hand Crossbow', speed: 3, roll: '3d', attack_bonus: 4, dmg_bonus: 1, bleed: 0, mt: 7, notes: '' },
          { name: 'Dodge',         speed: 0, roll: '3d', attack_bonus: 2, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],
        attributes_table: [
          { attr: 'Strength',     score: 14, half: 7,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Dexterity',    score: 18, half: 9,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Constitution', score: 16, half: 8,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Intelligence', score: 17, half: 8,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Wisdom',       score: 20, half: 10, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } },
          { attr: 'Charisma',     score: 22, half: 11, check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 2 } }
        ],
        items: {
          equipped: [{ name: 'Rapier' }, { name: 'Hand Crossbow' }, { name: 'Studded Leather' }],
          consumable: [{ quantity: 2, name: 'Healing Draught' }],
          ammunition: [{ quantity: 20, name: 'Bolt' }],
          other: [{ quantity: 1, name: 'Lute' }, { quantity: 5, name: 'Rations' }, { quantity: 1, name: 'Bedroll' }]
        },
        item_descriptions: [
          { name: 'Cloak of Resistance +1', description: 'Adds +1 to all saves; does not stack with other resistance items.' },
          { name: 'Lute of the Wandering Bard', description: 'Once per scene, grant Bardic Inspiration without spending the action.' }
        ],
        abilities: [
          { name: 'Bonus Feat',              description: 'Choose any 1st-level feat.' },
          { name: 'Magical Performance (3)', description: 'Learn a magical variant of any Performance skill, used both for mundane checks and to create a magical performance. Maintaining a performance takes a main action each turn; bardic spells can be cast as part of that action. Only advances on bard levels.' },
          { name: 'Bardic Spellcasting',     description: 'Cast a number of bardic spells as a main action while performing. Spells need not be prepared each day. Casting outside a performance takes twice as long.' },
          { name: 'Bardic Inspiration',      description: 'While performing, spend 1 mana (once per turn) to grant a pool of luck. Each point lets you or an ally reroll a single die before the initial check. Successes grant 1 luck (must be used before your next turn); a fumble awards luck to the DM instead.' },
          { name: 'Jack Of All Trades',      description: 'Treat all skills (except restricted skills) as trained, with effective ranks equal to half your level on checks where you have no ranks.' },
          { name: 'Better Lucky Than Good',  description: 'Spend 3 mana during a round you cannot act (e.g. surprise round). Attacks against you (including spells) are made with half as many dice (min 3). Enemies are unconsciously aware of the penalty.' },
          { name: 'Performance Feat',        description: 'Gain Familiar, Social Spell, Spell Focus (Enchantment), or Spell Focus (Illusion) as a bonus feat.' },
          { name: 'Silver Tongue',           description: '+1 inherent bonus to Persuasion and Deception checks; applies when using versatile performance.' },
          { name: 'Unsettling Words',        description: 'Spend a luck point from your performance before an enemy rolls; pick one of their dice to reroll.' },
          { name: 'Versatile Performance',   description: 'No description yet.' }
        ],
        spells: [
          { tier: 0, names: ['Mending'] },
          { tier: 1, names: ['Charm Person', 'Healing Word'] },
          { tier: 2, names: ['Suggestion'] }
        ],
        rituals: [{ tier: 1, names: ['Comprehend Languages', 'Detect Magic'] }],
        item_spells: [],
        active_effects: [],
        usable_spells: [],
        notes: [{ body: 'Placeholder note for the character.' }]
      )
    end

    # ---- 2. Bryn Ironvein -----------------------------------------------

    def bryn_ironvein
      attrs = { str: 19, dex: 11, con: 20, int: 10, wis: 13, cha: 7 }
      classes = [{ key: 'fighter', level: 3,
                   trained_skills: %w[athletics intimidate perception] }]
      base_data(
        id: 2,
        label: 'Bryn Ironvein — Tier 1 Fighter, pure martial',
        header: { name: 'Bryn Ironvein', player: 'Mira',
                  summary: 'Dwarf Fighter 3', tier: 1, bab: 5 },
        attributes: attrs,
        classes: classes,
        vitals: {
          hp:   { current: 0,  max: 20 },
          mana: { current: 8,  max: 8,  regen: 1 },
          toxicity: { current: 0, threshold: 7 },
          temp_hp: 0, moderate_damage: 0, major_damage: 0,
          combat_pool: 8, damage_reduction: 2, damage_resilience: 5
        },
        initiative: { dice_count: 6 },
        perception: { dice: 4, bonus: 2 },
        speed: 25,
        actions: [
          { name: 'Warhammer', speed: 3, roll: '6d', attack_bonus: 2, dmg_bonus: 1, bleed: 0, mt: 7, notes: '' },
          { name: 'Dodge',     speed: 0, roll: '3d', attack_bonus: 0, dmg_bonus: nil, bleed: nil, mt: nil, notes: '' }
        ],
        attributes_table: [
          { attr: 'Strength',     score: 19, half: 9,  check: { dice: 4, bonus: 0 }, save: { dice: 4, bonus: 0 } },
          { attr: 'Dexterity',    score: 11, half: 5,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Constitution', score: 20, half: 10, check: { dice: 4, bonus: 0 }, save: { dice: 4, bonus: 0 } },
          { attr: 'Intelligence', score: 10, half: 5,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Wisdom',       score: 13, half: 6,  check: { dice: 3, bonus: 2 }, save: { dice: 3, bonus: 0 } },
          { attr: 'Charisma',     score: 7,  half: 3,  check: { dice: 3, bonus: 0 }, save: { dice: 3, bonus: 0 } }
        ],
        items: {
          equipped: [{ name: 'Warhammer' }, { name: 'Tower shield' }, { name: 'Chain mail' }],
          consumable: [{ quantity: 1, name: 'Healing Draught' }],
          ammunition: [],
          other: [{ quantity: 3, name: 'Javelin' }, { quantity: 1, name: 'Whetstone' },
                  { quantity: 5, name: 'Rations' }, { quantity: 28, name: 'Gold' }]
        },
        item_descriptions: [],
        abilities: [
          { name: 'Darkvision',         description: 'No description yet.' },
          { name: 'Dwarven Resilience', description: 'No description yet.' },
          { name: 'Stonecunning',       description: 'No description yet.' },
          { name: 'Weapon Training',    description: 'No description yet.' },
          { name: 'Armor Training',     description: 'No description yet.' }
        ],
        spells: [], rituals: [], item_spells: [],
        active_effects: [], usable_spells: [], notes: []
      )
    end

    # ---- 3. Veyl Aetheris -----------------------------------------------

    def veyl_aetheris
      attrs = { str: 7, dex: 17, con: 11, int: 17, wis: 11, cha: 13 }
      classes = [{ key: 'arcane_trickster', level: 4,
                   trained_skills: %w[arcana stealth larceny sleight_of_hand deception persuasion perception game_chess] }]
      base_data(
        id: 9,
        label: 'Veyl Aetheris — Tier 2 Arcane Trickster (Archetype demo)',
        header: { name: 'Veyl Aetheris', player: nil,
                  summary: 'High Elf Arcane Trickster 4', tier: 2, bab: 4 },
        attributes: attrs,
        classes: classes,
        vitals: {
          hp:   { current: 18, max: 22 },
          mana: { current: 12, max: 16, regen: 2 },
          toxicity: { current: 0, threshold: 7 },
          temp_hp: 0, moderate_damage: 0, major_damage: 0,
          combat_pool: 6, damage_reduction: 1, damage_resilience: 3
        },
        initiative: { dice_count: 5 },
        perception: { dice: 4, bonus: 0 },
        speed: 30,
        actions: [
          { name: 'Shortbow', speed: 2, roll: '4d', attack_bonus: 3, dmg_bonus: 0, bleed: 0, mt: 7, notes: '' },
          { name: 'Dagger',   speed: 1, roll: '3d', attack_bonus: 2, dmg_bonus: 0, bleed: 0, mt: 6, notes: '' },
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
        items: {
          equipped: [{ name: 'Shortbow' }, { name: 'Dagger' }, { name: 'Studded Leather' }],
          consumable: [],
          ammunition: [{ quantity: 18, name: 'Arrow' }],
          other: [{ quantity: 1, name: 'Thieves Tools' }, { quantity: 1, name: 'Component Pouch' }]
        },
        item_descriptions: [],
        abilities: [
          { name: 'Low-Light Vision',     description: 'No description yet.' },
          { name: 'Keen Senses',          description: 'No description yet.' },
          { name: 'Elven Magic',          description: 'No description yet.' },
          { name: 'Trapfinding',          description: 'No description yet.' },
          { name: 'Sneak Attack',         description: 'No description yet.' },
          { name: "Thieves' Cant",        description: 'No description yet.' },
          { name: 'Arcane Spellcasting',  description: 'No description yet.' },
          { name: 'Danger Sense',         description: 'No description yet.' },
          { name: 'Combat Trickery',      description: 'No description yet.' },
          { name: 'Mage Hand Legerdemain', description: 'No description yet.' },
          { name: 'Elemental Dart',       description: 'No description yet.' }
        ],
        spells: [
          { tier: 0, names: ['Light', 'Message'] },
          { tier: 1, names: ['Fire Dart', 'Silent Portal'] },
          { tier: 2, names: ['Hideous Laughter'] }
        ],
        rituals: [], item_spells: [],
        active_effects: [
          { caster: 'Ash Windmere', source: 'Bardic Inspiration', rounds_left: 3 }
        ],
        usable_spells: [
          { name: 'Fire Dart',         casting_time: '1 action', mana_cost: 1, save_tn: nil },
          { name: 'Silent Portal',     casting_time: '1 action', mana_cost: 2, save_tn: 7 },
          { name: 'Hideous Laughter',  casting_time: '1 action', mana_cost: 3, save_tn: 7 }
        ],
        notes: []
      )
    end

    # --------------------------------------------------------------------

    # Build the demo Hash. Adds `skills` derived from `classes` +
    # `attributes` via Proficiencies + DiceResolution, so ranks /
    # dice / bonus are never hand-set.
    def base_data(classes:, attributes:, **rest)
      rest[:attributes] = attributes
      rest[:classes]    = classes
      rest[:skills]     = compute_skills(classes, attributes)
      rest
    end

    # For each (class_key, level, trained_skill) triple, compute the
    # rate, the rank contribution, the driving attribute, the
    # Direct Prowess (ranks + floor(attribute/2)), and the
    # translated dice / bonus. Aggregates across class entries when
    # a Creature multi-classes the same trained skill — each class
    # contributes its own rate × level via Ranks.ranks_for_skill,
    # and the totals are summed.
    def compute_skills(classes, attributes)
      acc = {}
      classes.each do |entry|
        class_key = entry[:key]
        level     = entry[:level]
        entry[:trained_skills].each do |skill_key|
          ranks = Proficiencies::Ranks.ranks_for_skill(class_key, level, skill_key, trained: true)
          attr_key = Proficiencies.attribute_for(skill_key)
          next unless attr_key
          slot = acc[skill_key] ||= { ranks: 0, attr_key: attr_key }
          slot[:ranks] += ranks
        end
      end
      acc.map do |skill_key, slot|
        attr_val = attributes[slot[:attr_key]] || 0
        # Direct Prowess (no floor lift, no substitution — we don't
        # have the Floor / Substitution abilities wired in yet).
        prowess  = slot[:ranks] + (attr_val / 2)
        dice, bonus = DiceResolution.translate_prowess(prowess)
        {
          name: pretty_skill_name(skill_key),
          ranks: slot[:ranks],
          dice: dice,
          bonus: bonus
        }
      end
    end

    # Render `perform_dance` as `Perform (Dance)`, `sleight_of_hand`
    # as `Sleight Of Hand`, `game_chess` as `Game (Chess)`, etc.
    def pretty_skill_name(key)
      if key.include?('_') && Proficiencies.skills.key?("#{key.split('_').first}_")
        family, *rest = key.split('_')
        return "#{family.capitalize} (#{rest.map(&:capitalize).join(' ')})"
      end
      key.split('_').map(&:capitalize).join(' ')
    end
  end
end
