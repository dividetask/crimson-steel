
module Display

  def self.display_bleed defender, bleed_log
    text_color = :light_white
    back_color = :on_red
    line = " #{defender.name} takes #{bleed_log.event_data[:bleed_damage]} bleed damage  (#{bleed_log.event_data[:bleed]} bleed)"

    print " " * 3
    print (" " * 2).colorize(text_color).send(back_color)
    print line.colorize(text_color).send(back_color)
    print (" " * 2).colorize(text_color).send(back_color)
    print " " * 3
    print "\n"

    print Display.draw_dice(bleed_log.event_dice)
  end

  def self.display_attack_message message, attack_roll_log, damage_notes
    text_color = :light_white
    back_color = :on_green
    text = []
    text << " #{message} (#{attack_roll_log.event_data[:success_count]}) "

		damage_mod = (damage_notes.weapon_base_damage - damage_notes.damage_reduction).to_s
    total_damage = damage_notes.total.to_s.rjust(2)
    bleed = damage_notes.bleed.to_s.rjust(2)
    base_damage  = damage_notes.weapon_base_damage.to_s.rjust(2)
    damage_reduction = damage_notes.damage_reduction.to_s.rjust(2)

    text << "#{total_damage} Damage, #{bleed} bleed"
    text << "#{damage_mod} (#{base_damage} Base - #{damage_reduction} DR)"
    longest_line_count = text.map { |t| t.length }.max
    text.map { |t| t + (" " * (longest_line_count - t.length) ) }
  end

  def self.display_attack combat_log
    #combat_log is expected to be <CombatLog>
  	#<CombatLog> is expected to have :event_dice and :event_data
    	#event_dice is expected to be a <Hash> containing <Symbols> for keys and <Roll> for values
  	#<Roll> is expected to have :dice_rolls and :die_values
			#die_values is expected to have die_values[:target] which is expected to hold an integer
#p "#{character.name} vs #{spider.name}"
#p "  Rolled #{result_log.last[:attack_log].attack_value},  #{result_log.last[:attack_log].damage_value} damage"
#p result_log.last[:attack_log].attack_value, result_log.last[:attack_log].damage_value, result_log.last[:attack_log].conditions[:bleed]
#p result_log.last[:attack_log].was_attack_successful, result_log.last[:attack_log].was_damage_successfull
#p result_log.last[:attack_log]

#p "#{result_log.last[:attack_log]} vs #{result_log.last[:defender_health]}"
				#result_log << {defender: character, attack_log: attack_details}
#p ''

		text_color = :white
    back_color = :on_black
		attack_roll_log = combat_log.event_data[:attack_roll_log] || combat_log

		damage_roll_log = combat_log.event_data[:damage_notes]
		damage_success = damage_roll_log == nil ? false : damage_roll_log.was_success
		hit_success = attack_roll_log.event_data[:was_success]


    width = IO.console.winsize[1]
    text = []

    if hit_success and damage_success #Success!
      text_color = :light_white
      back_color = :on_green
    	text = Display.display_attack_message("Hit",attack_roll_log, combat_log.event_data[:damage_notes])
    	#text = Display.display_hit_text(attack_roll_log, combat_log.event_data[:damage_notes])
    elsif hit_success and damage_success == false #Hit but no damage
      text_color = :light_white
      back_color = :on_red
      #text << "No Damage (#{attack_roll_log.event_data[:success_count]})"
    	text = Display.display_attack_message("No Damage",attack_roll_log, combat_log.event_data[:damage_notes])
    else #Miss
      text_color = :light_white
      back_color = :on_red
      text << "Miss (#{attack_roll_log.event_data[:success_count]})"
    end

		text.each do |line|
      print " " * 3
      print (" " * 2).colorize(text_color).send(back_color)
      print line.colorize(text_color).send(back_color)
      print (" " * 2).colorize(text_color).send(back_color)
      print " " * 3
      print "\n"
    end

    print "\n"

    event_dice = combat_log.event_dice

    print Display.draw_dice(attack_roll_log.event_dice)
    print Display.draw_dice(combat_log.event_dice) if attack_roll_log.event_data[:was_success]
    print "\n"
  end

	def self.draw_dice(dice)
  	#dice is expected to be <Roll> or <Hash> containing <Symbols> for keys, and <Roll> for values
  	#<Roll> is expected to have :dice_rolls and :die_values
		#die_values is expected to have die_values[:target] which is expected to hold an integer

    line_text = {header: "", top: "", middle: "", bottom: ""}
    write_dice_ascii_to_s(dice, line_text)

    if dice.is_a?(Roll)
      print "#{line_text[:top]}\n#{line_text[:middle]}\n#{line_text[:bottom]}\n"
    elsif dice.is_a?(Hash)
      print "#{line_text[:header]}\n#{line_text[:top]}\n#{line_text[:middle]}\n#{line_text[:bottom]}\n"
    end
	end

	def self.write_dice_ascii_to_s(dice, line_text)
  	#dice is expected to be <Roll> or <Hash> containing <Symbols> for keys, and <Roll> for values
  	#Roll is expected to have :dice_rolls and :die_values
		#die_values is expected to have die_values[:target] which is expected to hold an integer
  	#line_text is expected to be a <Hash> which is expected to have the following keys each holding a <String>: :top, :middle, :bottom

		dice_spacing = 1
    dice_hash = dice.is_a?(Hash) ? dice : {default: dice}

		dice_hash.each do |key, dice_obj|
      line_text.each_value { |v| v << " " * dice_spacing }
      header_text = "#{key.to_s.capitalize} (TN #{dice_obj.die_values[:target]})"
      line_text[:header] << header_text
      dice_obj.dice_rolls.each do |num|
        text_color = num == 1 ? :red : (num == 10 ? :blue : (num >= dice_obj.die_values[:target] ? :green : :black))
        back_color = num == 1 ? :on_red : (num == 10 ? :on_blue : (num >= dice_obj.die_values[:target] ? :on_green : :on_light_white))

        digit = (num % 10).to_s
        line_text[:header] << "     "
        line_text[:top]    << "┌───┐".black.send(back_color)
        line_text[:middle] << "│ ".black.send(back_color) + digit.black.send(back_color) + " │".black.send(back_color)
        line_text[:bottom] << "└───┘".black.send(back_color)
        line_text.each_value { |v| v << " " * dice_spacing }
      end
      line_text[:header].slice!(-(header_text.length)..-1)
      line_text.each_value { |v| v << " " * (2 *dice_spacing) }
    end
	end

	def self.display_round_information(round, current_hp, max_hp)
    width = IO.console.winsize[1]
    text = "Round #{round} (#{current_hp}/#{max_hp} hp)"
    centered_text = text.center(width)

    print centered_text.blue.on_light_white
    print "\n"
	end

	def self.press_any_key
		puts "Press Enter to continue..."
		gets
	end
end


module RulesMathOld
  def self.is_character_concious(character_status)
    return ( (character_status.hp > 0) and (character_status.get_pain < character_status.get_remaining_dice) )
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

	def self.calclute_bleed_damage(character, bleed)
		return nil if bleed <= 0

		details = {base_damage: (1 + (bleed / 10).floor), bleed: bleed }
		bleed_roll = Roll.new(get_save(character, :con))
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
		return 0 unless weapon.category == :weapon
  	case weapon.get_weapon_category
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
end


