require 'io/console'
require 'colorize'

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

	def self.display_attack_1 combat_log
    #combat_log is expected to be <CombatLog>
  	#<CombatLog> is expected to have :event_dice and :event_data
    	#event_dice is expected to be a <Hash> containing <Symbols> for keys and <Roll> for values
  	#<Roll> is expected to have :dice_rolls and :die_values
			#die_values is expected to have die_values[:target] which is expected to hold an integer

		text_color = :white
    back_color = :on_black
		attack_roll_log = combat_log.event_data[:attack_roll_log] || combat_log

    width = IO.console.winsize[1]
    text = []

    if combat_log.event_data[:damage_notes] == nil
      text_color = :light_white
      back_color = :on_red
      text << "Miss (#{attack_roll_log.event_data[:success_count]})"
    elsif combat_log.event_data[:damage_notes].bleed == 0 and combat_log.event_data[:damage_notes].total == 0
      text_color = :light_white
      back_color = :on_red
      text << "No Damage (#{attack_roll_log.event_data[:success_count]})"
    else
      text_color = :light_white
      back_color = :on_green
    	text = Display.display_attack_message("Hit",attack_roll_log, combat_log.event_data[:damage_notes])
    	#text = Display.display_hit_text(attack_roll_log, combat_log.event_data[:damage_notes])
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

  def self.display_attack combat_log
    #combat_log is expected to be <CombatLog>
  	#<CombatLog> is expected to have :event_dice and :event_data
    	#event_dice is expected to be a <Hash> containing <Symbols> for keys and <Roll> for values
  	#<Roll> is expected to have :dice_rolls and :die_values
			#die_values is expected to have die_values[:target] which is expected to hold an integer

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
