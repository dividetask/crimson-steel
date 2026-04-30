# Start-of-turn stub. Walks the active Combatant through the start-of-
# turn pipeline:
#
#   1. Reset action dice to action_dice_max for this combatant.
#   2. Consume Shock against the new pool (per the conditions glossary,
#      Shock is consumed against the combat-pool refresh).
#   3. Resolve the Acid Counter (halve, deal halved value as Minor HP
#      damage).
#   4. For each Active Affliction, the player rolls a save (via the
#      reusable roll_stub). Successes/criticals come back from the
#      roll_stub Result inputs. Severity moves and effect-side outcomes
#      are previewed inline before commit.
#   5. Clear effects whose `ends_on_round` has passed.
#
# A single Confirm button at the bottom POSTs the entire bundle —
# every per-affliction Result/Crits — to /combat/start_of_turn, which
# applies the changes through Combat and Conditions and atomically
# rewrites the state YAMLs.
#
# Design notes:
# - Per-affliction roll_stub rows reuse the existing roll_stub partial
#   (bare_row mode under one shared <table>) so Luck/Insight UX is
#   identical to other roll surfaces.
# - "Affliction Severity" (the per-affliction potency counter) is the
#   value the saves modify — see docs/conditions/conditions_glossary.md.

helpers do
  def start_of_turn_stub
    combatant = COMBAT.current_combatant
    return start_of_turn_empty_message('No active combatant. Reroll initiative first.') unless combatant

    char = CHARACTER_LOOKUP.call(combatant['char_id'])
    return start_of_turn_empty_message("No character data for char_id=#{combatant['char_id']}.") unless char

    conditions = CONDITIONS_REGISTRY&.for_character(combatant['char_id'])
    return start_of_turn_empty_message('Conditions registry unavailable.') unless conditions

    afflictions = conditions.afflictions.keys.sort.map do |name|
      build_affliction_save_row(name, conditions.get_affliction(name), char)
    end

    erb :"stubs/_start_of_turn_stub", layout: false, locals: {
      stub_id:           SecureRandom.hex(4),
      combatant:         combatant,
      character_name:    char.name,
      action_dice_now:   combatant['action_dice'].to_i,
      action_dice_max:   COMBAT.action_dice_max(combatant['char_id']),
      shock:             conditions.shock,
      acid_counter:      conditions.acid_counter,
      acid_after_halve:  conditions.acid_counter / 2,
      hp_damage:         conditions.hit_point_damage,
      afflictions:       afflictions,
      round:             COMBAT.round
    }
  end

  private

  def start_of_turn_empty_message(text)
    %(<div class="start-of-turn-stub start-of-turn-stub-empty"><p class="dt-note">#{h(text)}</p></div>)
  end

  # One row's worth of inputs to roll_stub for a single affliction
  # save. Save dice = floor(save_attribute / 2) + save_ranks. The
  # Severity Save Penalty (floor(severity / Severity Divisor)) is
  # applied as a Competency Penalty; the conditions module will add
  # the same penalty server-side when it resolves the outcome, so we
  # show it here only as a label hint.
  def build_affliction_save_row(name, info, char)
    save_attr = (info['save_attribute'] || 'con').to_sym
    attribute_score = char.attribute(save_attr)
    save_rank = char.save_ranks[save_attr.to_s].to_i

    base_dice = (attribute_score / 2) + save_rank
    minimum_dice = (DICE_SYSTEM.dice_resolution_config['Minimum Dice Count'] || 6).to_i
    dice_count = [base_dice, minimum_dice].max

    {
      name:           name,
      label:          start_of_turn_affliction_label(name),
      severity:       info['severity'].to_i,
      category:       info['category'],
      save_attribute: save_attr.to_s,
      check_name:     "#{start_of_turn_affliction_label(name)} Save (#{save_attr.upcase})",
      dice_count:     dice_count,
      tn:             (DICE_SYSTEM.dice_resolution_config['Base Target Number'] || 6).to_i,
      starting_value: 0
    }
  end

  def start_of_turn_affliction_label(name)
    name.to_s.tr('_', ' ').split.map(&:capitalize).join(' ')
  end
end
