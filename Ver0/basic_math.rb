#class BasicMath
module RulesMath
#module BasicMath
  def self.is_character_concious(combat_tracker)
    return ( (combat_tracker.hp > 0) and (combat_tracker.deep_wound * 2 < get_combat_pool(combat_tracker.defender)) )
  end

  def self.get_check_details(attacker, defender, attack_type)
		attack_tn, dodge_tn = [:melee, :magic_melee].include?(attack_type) ? [7,7] : [9,9]

    damage_tn = 7 # Needs to be fixed
    attack_tn += get_defense_tn_mod(defender, attack_type) - get_attack_tn_mod(attacker, attack_type)
    dodge_tn += get_attack_tn_mod(attacker, attack_type) - get_defense_tn_mod(defender, attack_type)

		starting_failures = [0, attack_tn - 9].max
		starting_successes = [0, 4 - attack_tn].max
		attack_tn = [4, [9, attack_tn].min].max
		dodge_tn = [4, [9, dodge_tn].min].max

		return [attack_tn, damage_tn, dodge_tn, starting_successes, starting_failures]
	end

  def self.get_weapon_category(weapon_type)
  	return {greataxe: :heavy, battleaxe: :medium_1h, longbow: :ranged}[weapon_type]
  end

  def self.calculate_deep_wound(attacker, defender, damage_notes)
  	deep_wound_mod = 3 + get_density_disparity_dr(attacker, defender) + defender.armor.bonus.to_i
    deep_wound_mod += 1 if defender.character_sheet.character_class == :barbarian
    return [0, damage_notes.total - deep_wound_mod].max
  end

	def self.calclute_bleed_damage(defender, bleed)
		return nil if bleed <= 0

		details = {base_damage: (1 + (bleed / 10).floor), bleed: bleed }
		bleed_roll = Roll.new(get_save(defender, :con))
		#details[:bleed_damage] = [0, [details[:base_damage] + 1, details[:base_damage] - bleed_roll.dice_results].min].max
		details[:bleed_damage] = [0, [details[:base_damage], details[:base_damage] - bleed_roll.dice_results].min].max
		details[:bleed_damage] += 1 if bleed_roll.dice_results <= -2 #Handle Fumble

		return CombatLog.new(:bleed_save, {bleed: bleed_roll}, details)
	end

  def self.make_attack_roll(attack_type, number_of_attack_dice, number_of_dodge_dice, check_details)
    event_dice, success_count = Roll.attack(attack_type, number_of_attack_dice, number_of_dodge_dice, check_details)
    details = {hit?: success_count >= 2, event_dice: event_dice }

		return CombatLog.new(attack_type, event_dice, {was_success: success_count >= 2, success_count: success_count} )
  end

  def self.make_damage_roll(attacker, defender, check_details, attack_roll_log)
  	damage_notes = Damage.new

    damage_notes.set(:damage_reduction, get_dr(attacker, defender))
    damage_notes.set(:weapon_base_damage, get_base_weapon_damage(attacker, attacker.weapon))
    damage_notes.set(:physical, damage_notes.weapon_base_damage + attack_roll_log.event_data[:success_count] - damage_notes.damage_reduction)

    attacker.weapon.bonus_damage_list.each do |damage_formula|
      dice_values = {target: check_details.attack_tn, crit: 2, fumble: 0}
      dice_values[:crit] = 3 if damage_formula.name == :emotional

      damage_notes.add_roll(damage_formula.name, Roll.new(damage_formula.number_of_dice, dice_values))
      damage_notes.increment(:rolled_typed_damage, damage_notes.damage_rolls[damage_formula.name].dice_results + damage_formula.static_amount.to_i)
    end

    damage_notes.set(:bleed, damage_notes.physical >= 0 ? damage_notes.physical + 5 : 0)

    damage_notes.set(:typed_damage, damage_notes.rolled_typed_damage + [0, damage_notes.physical].min) #Remaining Damage Reduction is applied to Typed
		damage_notes.set(:was_success, ( damage_notes.typed_damage > 0 or damage_notes.physical > 0 or damage_notes.bleed > 0 ) )
    damage_notes.set(:physical, [0, damage_notes.physical].max)
    damage_notes.set(:typed_damage, [0, damage_notes.typed_damage].max)
    damage_notes.set(:total, damage_notes.physical + damage_notes.typed_damage)
    damage_notes.set(:deep_wound, calculate_deep_wound(attacker, defender, damage_notes))

    damage_notes.set(:bleed, -5) if damage_notes.damage_rolls[:fire] and damage_notes.damage_rolls[:fire] > 0

    event_data = {damage_notes: damage_notes, attack_roll_log: attack_roll_log}
		return CombatLog.new(:no_damage, damage_notes.damage_rolls, event_data) unless damage_notes.was_success
		return CombatLog.new(:damage, damage_notes.damage_rolls, event_data)
  end

  def self.get_base_weapon_damage(character, weapon)
  	case get_weapon_category(weapon.weapon_type)
    when :light
  		return weapon.bonus + get_quarter_mod(character, :str) - 2
    when :medium_1h
  		return weapon.bonus + get_quarter_mod(character, :str)
    when :medium_2h
  		return weapon.bonus + get_half_mod(character, :str)
    when :heavy
  		return weapon.bonus + get_half_mod(character, :str) + 2
    when :ranged
  		return weapon.bonus + get_quarter_mod(character, :str)
    end
  end

  def self.get_quarter_mod(character, attr)
    return character.character_sheet[attr] / 4
  end

  def self.get_half_mod(character, attr)
    return character.character_sheet[attr] / 2 
  end

  def self.get_save(character, attr)
		#This needs to add for magic item bonuses
  	return get_half_mod(character, attr)
  end

  def self.calculate_skill_ranks(character, priority)
  	return 2 + ( (character.character_sheet.level * priority) / 3)
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

	def self.get_combat_pool(character)
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

	def self.get_max_hp(character)
  	density = get_density(character.character_sheet.level)
  	return (character.character_sheet.con / 2) if density == 0
    return (character.character_sheet.con * density)
	end

  def self.get_skill_tn_mod(character, skill)
  	return (character.character_sheet[skill] - 1) / 5
  end

  def self.get_skill_bonus_dice(character, skill)
  	return ((character.character_sheet[skill] - 1) % 5) + 1
  end

  def self.get_skill_attr(skill)
  	 {melee: :dex, heal: :wis, ranged: :dex}[skill]
  end

  def self.get_skill_attr_dice(character, skill)
    return get_half_mod(character, get_skill_attr(skill))
  end

  def self.get_max_dice(character, skill)
    return get_skill_bonus_dice(character, skill) + get_skill_attr_dice(character, skill)
  end

  def self.get_defense_tn_mod(character, attack_type)
  	shield_bonus = character.shield ? character.shield.bonus : 0

  	if attack_type == :melee or attack_type == :magic_melee
      return character.weapon.bonus + shield_bonus + get_skill_tn_mod(character, :melee) 
    elsif attack_type == :ranged or attack_type == :magic_ranged
      return shield_bonus
    else
      p "This should never happen"
    end
  end

  def self.get_attack_tn_mod(character, attack_type)
  	if attack_type == :melee or attack_type == :magic_melee
      return character.weapon.bonus + get_skill_tn_mod(character, :melee) 
    elsif attack_type == :ranged or attack_type == :magic_ranged
      return character.weapon.bonus + get_skill_tn_mod(character, :ranged) 
    else
      p "This should never happen"
    end
  end

  def self.get_dr(attacker, defender)
  	return defender.armor.get_dr + get_density_disparity_dr(attacker, defender)
  end
end


