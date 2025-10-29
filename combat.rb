
class Damage
  attr_reader :damage_type, :damage_severity, :damage_amount
	#damage_severity: 0 - none, 1 - minor, 2 - moderate, 3 - major
  def initialize(dt, ds, da); @damage_type, @damage_severity, @damage_amount = dt, ds, da; end
	def get_pain; return @damage_type == 3 ? @damage_amount * 2 : 0; end
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

class ProbAttack
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
