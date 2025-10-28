
class BasicCombat
  attr_reader :attacker, :defender, :attack_type, :combat_tracker, :combat_history, :display_action  	# Can be read outside class, but not written

  def initialize(attacker, defender, display_action = true)
		@attacker, @defender, @display_action = attacker, defender, display_action
    @attack_type = {melee_max_dice: :melee, ranged_mox_dice: :ranged}[@attacker.action_plan]
    @combat_tracker = CombatTracker.new(@attacker, @defender, @attack_type)
		@combat_history = []
	end

	def simulate_combat
    round = 1
  	while (RulesMath.is_character_concious(@combat_tracker) == true)
      Display.display_round_information(round, @combat_tracker.hp, RulesMath.get_max_hp(@defender)) if @display_action

      simulate_round
      Display.press_any_key
      round = round + 1
    end
  end

	def simulate_round
		remaining_dice = RulesMath.get_combat_pool(@attacker)
		round_history = []

    number_of_dodge_dice = 0
    number_of_dodge_dice = 4 if @defender.action_plan == :dodge_4

		while remaining_dice > 0 and @combat_tracker.hp > 0 and RulesMath.get_combat_pool(@defender) > @combat_tracker.deep_wound * 2
			number_of_dice = [remaining_dice, RulesMath.get_max_dice(@attacker, @attack_type)].min
			remaining_dice -= number_of_dice

			last_attack_log = @combat_tracker.handle_attack(number_of_dice, number_of_dodge_dice)
			round_history << last_attack_log

      Display.display_attack last_attack_log if @display_action
		end
    bleed_log = RulesMath.calclute_bleed_damage(@defender, @combat_tracker.bleed)
    if bleed_log
      round_history << bleed_log
      bleed_damage = bleed_log.event_data[:bleed_damage]
      Display.display_bleed(@defender, bleed_log)
      @combat_tracker.apply_damage(bleed_log.event_data[:bleed_damage]) if bleed_damage > 0
    end
		@combat_history << round_history
	end
end

