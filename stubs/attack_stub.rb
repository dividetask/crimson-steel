# Sinatra helper that renders the attack_stub partial. The stub is
# rule-ignorant and used by both melee and ranged flows: callers hand
# it the attacker's pre-computed weapon stats, the candidate targets
# (each with its own list of concrete defense options expanded from
# DummyData::DEFENSES_CATALOG), and the lists of ally / target reactions. The
# stub walks the DM through:
#
#   1. Select Target
#   2. Select Weapon
#   3. Select Attack Dice Count
#   4. Select Defense (Nothing / Dodge / Parry-with-X / Block-with-X)
#   5. Select Ally Reactions
#   6. Roll attack (and any rolled defense / ally reactions) via roll_stub
#   7. Select Target Reactions
#   8. Confirm damage, bleed, threshold, afflictions
#
# Steps with a single (or zero) option auto-advance. The final Submit
# dispatches an `attack:confirm` CustomEvent on the stub root with
# the full chosen payload; the host page decides what to do with it.

helpers do
  def attack_stub(attacker:, targets:, ally_reactions: [], luck_sources: [],
                  title: 'Attack',
                  die_size: DICE_SYSTEM.dice_resolution_config['Die Size'],
                  base_tn: DICE_SYSTEM.dice_resolution_config['Base Target Number'])
    erb :"stubs/_attack_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      title: title,
      attacker: attacker,
      targets: targets,
      ally_reactions: ally_reactions,
      luck_sources: luck_sources,
      die_size: die_size,
      base_tn: base_tn
    }
  end
end
