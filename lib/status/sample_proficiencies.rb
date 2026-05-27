module Status
  # Sample Proficiencies for the Proficiencies sub-view of the Status
  # page. Hand-built (not loaded through the live Proficiencies domain).
  # Each scenario is one Creature paired with a curated list of Skill
  # queries that together exercise every branch of the Compute Roll
  # inputs pipeline: Direct Prowess, Floor Ability lift, Substitution,
  # Floor + Substitution interaction, Restricted Skills, Save keys
  # (attribute override), Set Skill prefix match, and the
  # Non-Proficiency Penalty.
  #
  # Defaults from `proficiencies_config.yaml`:
  #   - Attribute Contribution Divisor: 2
  #   - Non-Proficiency Penalty Value: -2
  #   - Restricted Skills: [restricted_magic]
  #   - Floor Ability: jack_of_all_trades
  #   - Substitution Ability: versatile_performance
  #
  # Dice resolution prowess translation (from dice_resolution_config.yaml):
  #   - Minimum Dice Count: 6
  #   - Dice Count Range: 5
  module SampleProficiencies
    module_function

    def scenarios
      [vanilla_fighter, bard_with_floor, bard_with_substitution, bard_with_both]
    end

    # ---- 1. Vanilla Fighter (no Floor, no Substitution) -----------------

    def vanilla_fighter
      {
        label: 'Vanilla Fighter — Direct Prowess only',
        creature_summary: {
          name: 'Bryn Ironvein',
          klass: 'Fighter 4',
          tier: 2,
          abilities: [],
          attributes: { str: 4, dex: 3, con: 4, int: 1, wis: 2, cha: 0 }
        },
        rows: [
          row(key: 'athletics', attr: 'str', ranks: 6, attr_value: 4,
              note: 'Aligned-rate Skill trained at Fighter 4 → ranks 6'),
          row(key: 'stealth', attr: 'dex', ranks: 0, attr_value: 3,
              note: 'Untrained — Non-Proficiency Penalty applies'),
          row(key: 'craft_blacksmith', attr: 'int', ranks: 6, attr_value: 1,
              prefix_match: 'craft_',
              note: 'Set Instance resolves through `craft_` prefix → Aligned for Fighter'),
          row(key: 'restricted_magic', attr: 'int', ranks: 0, attr_value: 1,
              restricted: true,
              note: 'Restricted Skill: even with Floor Ability the floor would not apply'),
          row(key: 'con_save', attr: 'con', ranks: 6, attr_value: 4,
              attribute_override: 'con', no_catalog: true,
              note: 'Save key — no catalog entry, attribute_override = con')
        ]
      }
    end

    # ---- 2. Bard with jack_of_all_trades (Floor Ability) ----------------

    def bard_with_floor
      {
        label: 'Bard with `jack_of_all_trades` — Floor Ability lifts ranks',
        creature_summary: {
          name: 'Cottonballs',
          klass: 'Bard 4',
          tier: 2,
          abilities: [{ name: 'jack_of_all_trades', level_for_ability: 4 }],
          attributes: { str: 2, dex: 4, con: 3, int: 3, wis: 3, cha: 6 }
        },
        rows: [
          row(key: 'history', attr: 'int', ranks: 0, attr_value: 3,
              floor_lift: 2, floor_source: 'jack_of_all_trades @ 4 → floor(4 / 2) = 2',
              note: 'Floor lifts ranks 0 → 2; Non-Proficiency Penalty no longer applies'),
          row(key: 'athletics', attr: 'str', ranks: 6, attr_value: 2,
              floor_lift: 2, floor_source: 'jack_of_all_trades @ 4 → 2 (does not apply; actual ranks 6 > 2)',
              note: 'Actual ranks already exceed Floor minimum — Direct uses 6'),
          row(key: 'restricted_magic', attr: 'int', ranks: 0, attr_value: 3,
              restricted: true,
              floor_lift: 0, floor_source: 'Restricted Skill — Floor cannot apply',
              note: 'Restricted: Floor does not lift; Non-Proficiency Penalty applies'),
          row(key: 'perform_sing', attr: 'cha', ranks: 6, attr_value: 6,
              prefix_match: 'perform_',
              note: 'Bard `perform_sing`: not in unaligned list, inverse-form default → aligned (ranks 6)'),
          row(key: 'cha_save', attr: 'cha', ranks: 6, attr_value: 6,
              attribute_override: 'cha', no_catalog: true,
              floor_lift: 0, floor_source: 'No catalog entry — Floor does not apply',
              note: 'Save with override: Floor never applies to keys without a catalog entry')
        ]
      }
    end

    # ---- 3. Bard with versatile_performance (Substitution) -------------

    def bard_with_substitution
      {
        label: 'Bard with `versatile_performance` — Substitution can beat Direct',
        creature_summary: {
          name: 'Ash Windmere',
          klass: 'Bard 4',
          tier: 2,
          abilities: [{ name: 'versatile_performance', level_for_ability: 4 }],
          attributes: { str: 2, dex: 4, con: 3, int: 3, wis: 3, cha: 6 }
        },
        rows: [
          row(key: 'deception', attr: 'cha', ranks: 0, attr_value: 6,
              substitution: { source: 'perform_sing', source_attr: 'cha', source_ranks: 4, source_attr_value: 6, source_prowess: 7 },
              note: 'Direct Prowess 0+3+(-2)=1; Substituted (perform_sing) 4+3=7. Substitution wins.'),
          row(key: 'acrobatics', attr: 'dex', ranks: 0, attr_value: 4,
              substitution: { source: 'perform_dance', source_attr: 'cha', source_ranks: 4, source_attr_value: 6, source_prowess: 7 },
              note: 'Substitution attribute (cha) differs from queried attribute (dex). Sub wins 7 > 0.'),
          row(key: 'persuasion', attr: 'cha', ranks: 5, attr_value: 6,
              substitution: { source: 'perform_string', source_attr: 'cha', source_ranks: 2, source_attr_value: 6, source_prowess: 5 },
              note: 'Direct 5+3=8 vs Sub 2+3=5. Direct wins.'),
          row(key: 'persuasion_tie', display_key: 'persuasion (tie)', attr: 'cha', ranks: 3, attr_value: 4,
              substitution: { source: 'perform_string', source_attr: 'cha', source_ranks: 3, source_attr_value: 4, source_prowess: 5 },
              note: 'Tie at Prowess 5; Direct Prowess wins ties.'),
          row(key: 'stealth', attr: 'dex', ranks: 0, attr_value: 4,
              note: 'No Substitution Map entry targets `stealth` → no Substituted Prowess produced.')
        ]
      }
    end

    # ---- 4. Bard with both abilities -----------------------------------

    def bard_with_both
      {
        label: 'Bard with both abilities — Floor lifts Direct, Substitution unaffected',
        creature_summary: {
          name: 'Pippin Hoofstride',
          klass: 'Bard 4',
          tier: 2,
          abilities: [
            { name: 'jack_of_all_trades',  level_for_ability: 4 },
            { name: 'versatile_performance', level_for_ability: 4 }
          ],
          attributes: { str: 2, dex: 4, con: 3, int: 3, wis: 3, cha: 6 }
        },
        rows: [
          row(key: 'deception', attr: 'cha', ranks: 0, attr_value: 6,
              floor_lift: 2, floor_source: 'jack_of_all_trades @ 4',
              substitution: { source: 'perform_act', source_attr: 'cha', source_ranks: 1, source_attr_value: 6, source_prowess: 4, no_floor: true },
              note: 'Direct: floor 2, prowess 2+3=5. Sub: no floor on source, 1+3=4. Direct wins.'),
          row(key: 'acrobatics', attr: 'dex', ranks: 0, attr_value: 2,
              floor_lift: 2, floor_source: 'jack_of_all_trades @ 4',
              substitution: { source: 'perform_dance', source_attr: 'cha', source_ranks: 8, source_attr_value: 6, source_prowess: 11, no_floor: true },
              note: 'Direct: floor 2, prowess 2+1=3. Sub: 8+3=11 (no floor on source). Substitution wins big.'),
          row(key: 'restricted_magic', attr: 'int', ranks: 0, attr_value: 3,
              restricted: true,
              floor_lift: 0, floor_source: 'Restricted — Floor does not apply',
              note: 'Restricted Skill: Floor blocked; Non-Proficiency Penalty still applies.'),
          row(key: 'history', attr: 'int', ranks: 0, attr_value: 3,
              floor_lift: 2, floor_source: 'jack_of_all_trades @ 4',
              note: 'No substitution for `history`; Floor lifts ranks 0 → 2 normally.')
        ]
      }
    end

    # ---- row builder ---------------------------------------------------

    NON_PROFICIENCY_PENALTY = -2
    ATTRIBUTE_DIVISOR = 2
    MIN_DICE = 6
    DICE_RANGE = 5

    def row(key:, attr:, ranks:, attr_value:,
            display_key: nil,
            attribute_override: nil, no_catalog: false,
            prefix_match: nil, restricted: false,
            floor_lift: 0, floor_source: nil,
            substitution: nil,
            note: nil)
      effective_ranks = [ranks, floor_lift].max
      attr_contrib = (attr_value / ATTRIBUTE_DIVISOR).floor
      penalty = effective_ranks.zero? ? NON_PROFICIENCY_PENALTY : 0
      direct_prowess = effective_ranks + attr_contrib + penalty

      sub_prowess = substitution&.dig(:source_prowess)
      proficiency_prowess = sub_prowess && sub_prowess > direct_prowess ? sub_prowess : direct_prowess

      dice_cap, competency = translate_prowess(proficiency_prowess)

      {
        key: key,
        display_key: display_key || key,
        attribute: attr,
        attribute_override: attribute_override,
        no_catalog: no_catalog,
        prefix_match: prefix_match,
        restricted: restricted,
        ranks: ranks,
        attr_value: attr_value,
        floor_lift: floor_lift,
        floor_source: floor_source,
        effective_ranks: effective_ranks,
        attr_contrib: attr_contrib,
        non_proficiency_penalty: penalty,
        direct_prowess: direct_prowess,
        substitution: substitution,
        proficiency_prowess: proficiency_prowess,
        dice_cap: dice_cap,
        competency_modifier: competency,
        note: note
      }
    end

    # Mirror of dice_resolution's Translate Skill Prowess.
    def translate_prowess(prowess)
      bonus_penalty = (prowess.to_f / DICE_RANGE).floor
      remainder = prowess - bonus_penalty * DICE_RANGE
      dice_cap = MIN_DICE + remainder
      [dice_cap, bonus_penalty]
    end
  end
end
