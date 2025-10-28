require 'securerandom'

class CombatLog
  attr_reader :event_name, :event_dice, :event_data  	# Can be read outside class, but not written

  def initialize(event_name, event_dice, event_data)
    #event_dice is expected to be a <Hash> containing <Symbols> for keys and <Roll> for values
    raise ArgumentError, "options must be a <Hash>" unless event_dice.is_a?(Hash)
    raise ArgumentError, "all keys must be <Symbols>" unless event_dice.keys.all?(Symbol)
    raise ArgumentError, "all values must be <Roll>" unless event_dice.values.all?(Roll)
		@event_name, @event_dice, @event_data = event_name, event_dice, event_data
		@event_dice = {default: @event_dice.dup} unless @event_dice.is_a?(Hash)
	end

	def get_dice_values(dice_key = :default)
  	#consider removing
		@event_dice[dice_key]
	end
end

class Roll
  attr_reader :dice_results, :dice_rolls, :die_values  	# Can be read outside class, but not written
  @@deck = (1..10).to_a  																# Cannot be accessed outside class. Shared among all objects
  @@cheat_values = []						 												# Cannot be accessed outside class. Shared among all objects

  def initialize(number_of_dice, die_values = {})
		# number_of_dice 					is expected to be nil or an integer
		# dice_values 					 	is expected to be nil or a hash with zero or more of the following keys: fumble, crit, target, success, default
		@die_values = {fumble: -1, crit: 2, target: 9, success: 1, default: 0}.merge(die_values || {})
		@dice_rolls = Roll.roll_dice(number_of_dice)
		@dice_results = @dice_rolls.sum { |r| r == 1 ? @die_values[:fumble] : r == 10 ? @die_values[:crit] : r >= @die_values[:target] ? @die_values[:success] : @die_values[:default]}
  end

	def self.cheat cheat_values
		@@cheat_values = cheat_values
	end

	def self.get_rand
		return @@cheat_values.shift unless @@cheat_values.empty?
		return @@deck.shuffle!(random: SecureRandom)[0]
	end

	def self.roll_dice(number_of_dice)
		# number_of_dice 					is expected to be nil or an integer
		# returns an array of integers whose value is between 1 and 10

		return [] if (number_of_dice == nil or number_of_dice <= 0)
		return Array.new(number_of_dice) { Roll.get_rand }
	end

	def self.attack(attack_type, number_of_attack_dice, number_of_dodge_dice, check_details)
		event_dice = {}

		event_dice[:attack] = Roll.new(number_of_attack_dice, {target: check_details.attack_tn})
		event_dice[:dodge] = Roll.new(number_of_dodge_dice, {target: check_details.dodge_tn})

		success_count = (event_dice[:attack].dice_results + check_details.starting_successes)
		success_count -= (event_dice[:dodge].dice_results + check_details.starting_failures)

		return event_dice, success_count
	end

  def self.damage(attacker, defender, check_details)
    damage_notes = {damage_adjustment: nil, base_damage: nil, damage_reduction: nil, typed_damage: nil}
    event_dice = {}

    damage_notes[:damage_reduction] = RulesMath.get_dr(attacker, defender)
    damage_notes[:base_damage] = RulesMath.get_base_weapon_damage(attacker, attacker.weapon)
    damage_notes[:typed_damage] = 0

    attacker.weapon.bonus_damage_list.each do |damage_type, damage_dice|
      dice_values = {target: check_details.attack_tn, crit: 2, fumble: 0}
      dice_values[:crit] = 3 if damage_type == :emotional

      event_dice[damage_type] = Roll.new(damage_dice, dice_values)
      damage_notes[:typed_damage] += event_dice[damage_type].dice_results
    end

    damage_notes[:damage_adjustment] = damage_notes[:base_damage] - damage_notes[:damage_reduction]

		return CombatLog.new(:damage, event_dice, damage_notes)
  end
end

class Check
				# {attack_tn: <INT>, damage_tn: <INT>, dodge_tn: <INT>, starting_successes: <INT>, starting_failures: <INT>, use_weapon?: <BOOL>}
  attr_reader :attack_tn, :damage_tn, :dodge_tn, :starting_successes, :starting_failures  	# Can be read outside class, but not written

  def initialize(attacker, defender, attack_type)
		@attack_tn, @damage_tn, @dodge_tn, @starting_successes, @starting_failures = RulesMath.get_check_details(attacker, defender, attack_type)
	end
end

class CombatTracker
  attr_reader :attacker, :defender, :attack_type, :check_details, :combat_history, :hp, :bleed, :deep_wound  	# Can be read outside class, but not written

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
