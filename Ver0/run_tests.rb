
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

class NewCombatTracker
  attr_reader :attacker, :defender, :check_details, :combat_history, :hp, :bleed, :deep_wound  	# Can be read outside class, but not written

  def initialize(attacker, defender, attack_type)
		@attacker, @defender = attacker, defender
		@combat_history = []
		@hp = RulesMath.get_max_hp(@defender)
		@bleed = @deep_wound = 0
		set_attack_type(attack_type)
	end

	def update_health(hp_mod, bleed_mod, new_deep_wound)
  	@hp += hp_mod
  	@bleed += bleed_mod
    @deep_wound = new_deep_wound
  end

  def apply_damage(hp_mod)
  	@hp -= hp_mod
  end

	def set_attack_type(attack_type)
		@attack_type = attack_type
		if @check_details
			@check_details = @check_details.update(@attacker, @defender, @attack_type)
		else
			@check_details = Check.new(@attacker, @defender, @attack_type)
		end
	end

	def handle_bleed
		return nil if @bleed <= 0
    combat_log = RulesMath.calclute_bleed_damage(@defender, @bleed)
  	@hp -= combat_log.event_data[:bleed_damage]
		return combat_log
	end

  def handle_attack(number_of_attack_dice, number_of_dodge_dice)
		attack_roll_log = RulesMath.make_attack_roll(@attack_type, number_of_attack_dice, number_of_dodge_dice, @check_details)
    return attack_roll_log unless attack_roll_log.event_data[:was_success]
    damage_roll_log = RulesMath.make_damage_roll(@attacker, @defender, @check_details, attack_roll_log)

    #p damage_roll_log.event_data, damage_roll_log.event_data[:damage_notes].was_success
    return damage_roll_log unless damage_roll_log.event_data[:damage_notes].was_success

    @hp -= damage_roll_log.event_data[:damage_notes].total
    @bleed += damage_roll_log.event_data[:damage_notes].bleed
    @bleed = [0, @bleed].max  #damage_roll_log.event_data.bleed could be negative such as from a flaming weapon
    @deep_wound = damage_roll_log.event_data[:damage_notes].deep_wound

    return damage_roll_log
  end
end
module RunTests

	def self.test_cultist
		cultist = Character.get_cult_leaders_sheet
		lysander = Character.get_lysanders_sheet
		olga = Character.get_olgas_sheet
		basic_combat = BasicCombat.new(lysander, cultist, true)
	end
end
