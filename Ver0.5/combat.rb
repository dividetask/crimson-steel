ATTACK_SUCCESS_THRESHOLD = 2
WEAPON_THRESHOLDS_DEFAULTS = {pierce: 4, bludgeoning: 3, slashing: 5}
WEAPON_THRESHOLDS = {bite: 5, rapier: 4, club: 3, scimitar: 5, quarterstaff: 3, battleaxe: 5, greataxe: 5, longbow: 4, javelin: 4}
WEAPON_BLEEDMOD_DEFAULTS = {pierce: 3, bludgeoning: 5, slashing: 7}
WEAPON_BLEEDMOD = {bite: 3, rapier: 3, club: 5, scimitar: 7, quarterstaff: 5, battleaxe: 7, greataxe: 7, longbow: 3, javelin: 3}
EQUIPMENT_DR = {armor: {light: 1, natural: 2, medium: 3, heavy: 6}}
WEAPON_CATEGORY = {greataxe: :heavy, battleaxe: :medium_1h, longbow: :ranged, bite: :light}
ATTACK_TYPE = {heavy: :melee, medium_1h: :melee, light: :melee, ranged: :ranged}
WEAPON_STR_MOD = {heavy: 0.5, medium_2h: 0.5, medium_1h: 0.25, light: 0.25, ranged: 0.25}
WEAPON_BASE_MOD = {heavy: 2, medium_2h: 0, medium_1h: 0, light: -2, ranged: 0}

class Damage
  attr_reader :damage_type, :damage_severity, :damage_amount
	#damage_severity: 0 - none, 1 - minor, 2 - moderate, 3 - major
  def initialize(dt, ds, da); @damage_type, @damage_severity, @damage_amount = dt, ds, da; end
	def get_pain; return @damage_type => 3 ? @damage_amount * 2 : 0; end
end

class Equipment
  attr_reader :name, :category, :subcategory, :bonus, :additional_properties

	def initialize(name, category, subcategory, bonus, additional_properties = {})
		@name, @category, @subcategory, @bonus, @additional_properties = name, category, subcategory, bonus, additional_properties
	end

	def get_threshold; @additional_properties[:threshold] || WEAPON_THRESHOLDS[@subcategory] || 0; end
	def get_bleed_mod; WEAPON_BLEEDMOD[@subcategory] || 0; end
  def is_melee; return ATTACK_TYPE[WEAPON_CATEGORY[@subcategory]] == :melee; end
  def get_attack_type; return ATTACK_TYPE[WEAPON_CATEGORY[@subcategory]]; end
  def get_weapon_category; return WEAPON_CATEGORY[@subcategory]; end
	def get_dr; base_dr = EQUIPMENT_DR.dig(@category,@subcategory); return 0 unless base_dr; return base_dr + @bonus; end
  def get_base_weapon_damage(char); wt = WEAPON_CATEGORY[@subcategory]; return (char.str * WEAPON_STR_MOD[wt]).to_i + WEAPON_BASE_MOD[wt]; end
end

class Attack
  attr_reader :attack_value, :damage_value, :damage_list, :conditions, :was_attack_successful, :was_damage_successfull, :rolls, :notes
  def set(key, value); instance_variable_set("@#{key}", value); end
  def increment(key, amount = 1); current = instance_variable_get("@#{key}") || 0; instance_variable_set("@#{key}", current + amount); end
	def add_roll(key, value); (@rolls ||= {})[key] = value; end
	def add_notes(key, value); (@notes ||= {})[key] = value; end
	def define_notes(); @notes ||= {}; return @notes; end
	#def add_damage(key, value); (@damage_math ||= {})[key] = value; end
	def add_damage(damage); (@damage_list ||= []) << damage; end
	def update_damage_value(); @damage_value = (@damage_list || []).sum(&:damage_amount); end
	def update_was_damage_successfull(); update_damage_value; @was_damage_successfull = @damage_value > 0 or @conditions[:bleed] > 0; end
end

class InitiativeRoll < BaseRoll
	def self.roll(combatants)
		return combatants.map { |k,v| [k, InitiativeRoll.new(RulesMath.get_initiative(v).dup)] }.to_h
	end

	def to_s
		return @dice_rolls.sort.reverse.map { |v| v == 10 ? 'X' : v.to_s }.join
	end

	def to_i
		digits_before_decimal = 5
  	sorted = @dice_rolls.sort.reverse.map { |die| die - 1 }
		sorted << 9 # Tiebreaker, A [5, 1, 1, 1] vs B [5, 1]    this ensures A goes first
  	return sorted.map.with_index { |die, i| die.to_f * (10 ** (digits_before_decimal-i)) }.sum
	end

	def self.turn_order initiative_hash
		cleaned_results = initiative_hash.to_a.map { |v| [v[0], v[1].to_i] }
		return cleaned_results.sort_by { |v| v[1] }.reverse.map { |v| v[0] }
	end
end

class Roll < BaseRoll
  attr_reader :dice_results, :die_values

  def initialize(number_of_dice, die_values = {})
		# number_of_dice 					is expected to be nil or an integer
		# dice_values 					 	is expected to be nil or a hash with zero or more of the following keys: fumble, crit, target, success, default
		@die_values = {fumble: -1, crit: 2, target: 9, success: 1, default: 0}.merge(die_values || {})
		super(number_of_dice)
		@dice_results = @dice_rolls.sum do |r| 
			r == 1 ? @die_values[:fumble] : r == 10 ? @die_values[:crit] : r >= @die_values[:target] ? @die_values[:success] : @die_values[:default]
		end
  end

	def self.roll_dice(number_of_dice)
		# number_of_dice 					is expected to be nil or an integer
		# returns an array of integers whose value is between 1 and 10

		return [] if (number_of_dice == nil or number_of_dice <= 0)
		return Array.new(number_of_dice) { Roll.get_rand }
	end

	def self.attack(number_of_attack_dice, number_of_dodge_dice, attack_tn, dodge_tn, attack_success_mod)
		attack_details = Attack.new

		attack_details.add_roll(:attack, Roll.new(number_of_attack_dice, {target: attack_tn}))
		attack_details.add_roll(:dodge, Roll.new(number_of_dodge_dice, {target: dodge_tn}))

		attack_value = (attack_details.rolls[:attack].dice_results + attack_success_mod - attack_details.rolls[:dodge].dice_results)
		attack_details.set(:attack_value,	attack_value)
		attack_details.set(:was_attack_successful, attack_value >= ATTACK_SUCCESS_THRESHOLD)

		return attack_details
	end

  def self.damage(attacker, defender, weapon, attack_details)
    attack_details.add_damage(:damage_reduction, (-1 * RulesMath.get_dr(attacker, defender)))
    attack_details.add_damage(:base_damage, RulesMath.get_base_weapon_damage(attacker, weapon))
		check_details = Check.new(attacker, defender, weapon)

    weapon.additional_properties[:bonus_damage].each do |damage_type, damage_dice|
			dice_values = DAMAGE_TYPE_TR[:default].merge(DAMAGE_TYPE_TR[damage_type])
			dice_values[:target] = check_details.attack_tn unless dice_values[:target] #:target should be nil unless damage type has priority

			new_roll = Roll.new(damage_dice, dice_values)
			attack_details.add_roll(damage_type, new_roll)
    	attack_details.add_damage(damage_type, new_roll.dice_results)
    end

		return attack_details
  end
end
