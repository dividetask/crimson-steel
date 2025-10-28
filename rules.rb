MAJOR_DAMAGE = 3
MODERATE_DAMAGE = 2
MINOR_DAMAGE = 1
DAMAGE_TYPE_TN = {default: {target: nil, crit: 2, fumble: 0}, emotional: {crit: 3}}
DAMAGE_SEVERITY = {default: MODERATE_DAMAGE}

class CombatMath
  attr_reader :attacker_status, :defender_status, :attack_tn, :dodge_tn, :attack_success_mod
	def suprise_round_is_over; @is_in_combat = true; end

	def initialize(attacker, defender, is_in_combat = true)
		#expects attacker and defender to be <Character>
		@attacker_status = CharacterStatus.new(attacker)
		@defender_status = CharacterStatus.new(defender)
		@is_in_combat = is_in_combat
	end

	def roll_attack(weapon, number_of_attack_dice, number_of_dodge_dice)
		number_of_attack_dice = [number_of_attack_dice, @attacker_status.get_remaining_dice].min #make sure they have enough dice
		@attacker_status.spend_dice(number_of_attack_dice)
		update_check_tn(weapon, number_of_dodge_dice)
		
		return Roll.attack(number_of_attack_dice, number_of_dodge_dice, @attack_tn, @dodge_tn, @attack_success_mod)
	end

	def roll_damage(weapon, attack_details)
		notes = attack_details.define_notes
		attack_details.add_notes(:attacker_name, @attacker_status.character.name)
		attack_details.add_notes(:weapon, weapon.name)
		attack_details.add_notes(:defender_name, @defender_status.character.name)
    attack_details.add_notes(:damage_reduction, RulesMath.get_dr(@attacker_status.character, @defender_status.character))
    attack_details.add_notes(:base_damage, weapon.get_base_weapon_damage(@attacker_status.character))
    attack_details.add_notes(:physical_damage, notes[:base_damage] + attack_details.attack_value - notes[:damage_reduction])

    attack_details.add_notes(:threshold, weapon.get_threshold)
    attack_details.add_notes(:defender_resiliance, @defender_status.character.get_resilience)
    attack_details.add_notes(:minor_damage, [notes[:physical_damage], notes[:defender_resiliance]].min)
    attack_details.add_notes(:moderate_damage, [notes[:threshold], notes[:physical_damage] - notes[:minor_damage]].min)
    attack_details.add_notes(:major_damage, notes[:physical_damage] - notes[:moderate_damage] - notes[:minor_damage])

    attack_details.add_damage(Damage.new(:physical, MAJOR_DAMAGE, notes[:major_damage])) if notes[:major_damage] > 0
    attack_details.add_damage(Damage.new(:physical, MODERATE_DAMAGE, notes[:moderate_damage])) if notes[:moderate_damage] > 0
    attack_details.add_damage(Damage.new(:physical, MINOR_DAMAGE, notes[:minor_damage])) if notes[:minor_damage] > 0

    (weapon.additional_properties[:bonus_damage] || {}).each do |damage_type, damage_dice|
			dice_values = DAMAGE_TYPE_TN[:default].merge(DAMAGE_TYPE_TN[damage_type])
			dice_values[:target] = attack_details.rolls[:attack].die_values[:target] unless dice_values[:target] 

			new_roll = Roll.new(damage_dice, dice_values)
			attack_details.add_roll(damage_type, new_roll)
			damage_severity = DAMAGE_SEVERITY[damage_type] ? DAMAGE_SEVERITY[damage_type] : DAMAGE_SEVERITY[:default]
    	attack_details.add_damage(Damage.new(damage_type, damage_severity, new_roll.dice_results))
    end
		conditions = {bleed: 0}
		conditions[:bleed] = notes[:physical_damage] + weapon.get_bleed_mod if notes[:physical_damage] >= 0
		conditions[:bleed] = -5 if (attack_details.damage_list || []).any? { |dmg| dmg.damage_type == :fire and dmg.damage_amount > 0}
		attack_details.set(:conditions, conditions)

		attack_details.update_was_damage_successfull
		@defender_status.update_status(attack_details)

		return attack_details
	end

	private
  def update_check_tn(weapon, dodge_dice)  #PRIVATE
		@attack_tn, @dodge_tn = weapon.is_melee ? [7,7] : [9,9]

		@attack_tn -= 2 unless @is_in_combat
		@attack_tn -= 2 if dodge_dice == 0 and @attacker_status.character.character_class != :barbarian

    @attack_tn += get_attack_tn_mod(@attacker_status.character, weapon) - get_defense_tn_mod(@defender_status.character, weapon)
    @dodge_tn += get_defense_tn_mod(@defender_status.character, weapon) - get_attack_tn_mod(@attacker_status.character, weapon)

		@attack_success_mod = [0, 4 - @attack_tn].max #add starting successes
		@attack_tn -= [0, @attack_tn - 9].max #add starting failures
		@attack_tn = [4, [9, @attack_tn].min].max
		@dodge_tn = [4, [9, @dodge_tn].min].max
	end

  def get_defense_tn_mod(character, attacker_weapon)
		def_shield_bonus = character.equipment.map { |equip| equip.bonus if equip.category == :shield }.compact.sort.first

		return def_shield_bonus + RulesMath.get_skill_tn_mod(character, :melee) if def_shield_bonus
		# WE ARE ASSUMING THEY AREN'T PARRYING
		return 0
  end

  def get_attack_tn_mod(character, weapon)
		weapon_bonus = character.equipment.map { |wpn| wpn.bonus if wpn.is_melee }.compact.sort.first || 0
    return weapon_bonus + RulesMath.get_skill_tn_mod(character, :melee) if weapon.is_melee
    return weapon_bonus + RulesMath.get_skill_tn_mod(character, :ranged) 
  end
end

module RulesMath
	def self.adjust_for_status(character_status, skill)
		#character_status.character.character_sheet.dex
	end

	def self.get_max_attack_dice(character, weapon)
		return 4 + ((get_half_mod(character, :dex) + get_skill_ranks(character, weapon.get_attack_type)) % 6)
	end

	def self.get_max_combat_pool(character)
    dex_mod = get_half_mod(character, :dex)
  	character_sheet = character.character_sheet
  	if character_sheet.character_class == :animal
      return dex_mod + (character_sheet.level * 0.5).to_i 	if character_sheet.level >= 16
      return dex_mod + (character_sheet.level * 0.75).to_i 	if character_sheet.level >= 8
      return dex_mod + (character_sheet.level * 1.5).to_i		if character_sheet.level >= 4
      return dex_mod + (character_sheet.level * 2)
  	elsif character_sheet.character_class == :npc
      return dex_mod + (character_sheet.level * 0.75).to_i	if character_sheet.level >= 16
      return dex_mod + (character_sheet.level) 							if character_sheet.level >= 8
      return dex_mod + (character_sheet.level * 2.5).to_i
  	else
      return dex_mod + (character_sheet.level) 							if character_sheet.level >= 16
      return dex_mod + (character_sheet.level * 1.5).to_i 	if character_sheet.level >= 8
      return dex_mod + (character_sheet.level * 3) 					if character_sheet.level >= 4
      return dex_mod + (character_sheet.level * 4) 				
    end
  end

  def self.get_quarter_mod(character, attr)
    return character.character_sheet[attr] / 4
  end

  def self.get_half_mod(character, attr)
    return character.character_sheet[attr] / 2 
  end

	def self.get_max_hp(character)
  	density = get_density(character.level)
  	return (character.con / 2) if density == 0
    return (character.con * density * 2) if character.character_type == :beast and character.int <= 2
    return (character.con * density)
	end

  def self.get_initiative(character); return get_half_mod(character, :wis); end
  def self.get_skill_attr(skill); return {melee: :dex, heal: :wis, ranged: :dex}[skill]; end
	def self.get_skill_ranks(character, skill); return ((character.level * character.skills[skill]) / 3); end
  def self.get_skill_tn_mod(character, skill); return 1 - ((get_half_mod(character, :dex) + get_skill_ranks(character, skill)) % 6); end

  #def self.get_skill_bonus_dice(character, skill)
  	#return ((character.character_sheet[skill] - 1) % 5) + 1
  #end

  #def self.get_skill_attr_dice(character, skill)
    #return get_half_mod(character, get_skill_attr(skill))
  #end

  #def self.get_max_dice(character, skill)
    #return get_skill_bonus_dice(character, skill) + get_skill_attr_dice(character, skill)
  #end

  def self.get_dr(attacker, defender)
  	return defender.equipment.sum { |equip| equip.get_dr } + get_density_disparity_dr(attacker, defender) + defender.get_class_dr
  end

  def self.get_density_disparity_dr(attacker, defender)
  	return [0, get_density_dr(defender) - get_density_dr(attacker)].max
  end

  def self.get_density_dr(character)
  	density = get_density(character.character_sheet.level)
    return 0 if density == 0
    return 2 + ( (density - 1) * 5)
  end

  def self.get_density(level)
  	return 0 if level <= 0
  	return 1 if level < 4
  	return 2 if level < 8
  	return 3 if level < 16
  	return 4 if level < 32
    return 5
  end
end

