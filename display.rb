require 'io/console'
require 'colorize'

class Menu
  attr_reader :width, :col_width, :col_align
	def initialize(width); @width = width; @col_width = [nil]; @col_align = [nil]; end
	def display_header(msg); print "#{'=' * @width}\n#{msg.center(@width)}\n#{'=' * @width}\n"; end

	def update_width(msg_na2)
		avg_w = @width / msg_na2.map { |row| row.count }.max
		@col_width = Tools.rotatemap2d(msg_na2, ->(m, r, c) { m.length + 2 <= avg_w ? 0 : m.length + 2 }, ->(row, r) { row.max })
		@col_align = Array.new(@col_width.count) { :ljust }
		return if @col_width.count(0) == 0
		remaining = (@width - @col_width.sum) / @col_width.count(0)
		@col_width.map! { |nlen| nlen == 0 ? remaining : nlen }
	end

	def display_section(msg_na2)
		update_width(msg_na2)
		Tools.each2d(msg_na2, ->(msg, r, c) { print "#{@col_width[c] ? msg.send(@col_align[c],@col_width[c]) : msg}" }, ->(row, r) { print "\n" })
	end

	def display_table(align, header_a, msg_na2)
		update_width([header_a] + msg_na2)
		@col_align = align
		print "#{'═' * @width}\n"
		header_a.each.with_index { |msg,c| print msg.send(@col_align[c],@col_width[c]) }
		print "\n#{'═' * @width}\n"
		msg_na2.each { |row| row.each.with_index { |msg, c| print msg.send(@col_align[c],@col_width[c]) }; print "\n" unless row == msg_na2.last }
		print "\n#{'═' * @width}\n"
	end

	def display_adjacent_tables(align_na2, header_na2, msg_na3)
		spacer = 5
		header_a = header_na2[0] + [' ' * spacer] + header_na2[1]
		msg_na2 = msg_na3[0].zip(msg_na3[1]).map { |left, right| left + [' ' * spacer] + (right || []) }
  
		update_width([header_a] + msg_na2)
		@col_align = align_na2[0] + [:ljust] + align_na2[1]
		print "#{'═' * @col_width[0..align_na2[0].length-1].sum}#{' ' * @col_width[align_na2[0].length]}#{'═' * @col_width[(-1*align_na2[1].length)..-1].sum}\n"
#
		header_a.each.with_index { |msg,c| print msg.send(@col_align[c],@col_width[c]) }
		print "\n"
		print "#{'═' * @col_width[0..align_na2[0].length-1].sum}#{' ' * @col_width[align_na2[0].length]}#{'═' * @col_width[(-1*align_na2[1].length)..-1].sum}\n"
		msg_na2.each { |row| row.each.with_index { |msg, c| print msg.send(@col_align[c],@col_width[c]) }; print "\n" }
		print "#{'═' * @col_width[0..align_na2[0].length-1].sum}#{' ' * @col_width[align_na2[0].length]}#{'═' * @col_width[(-1*align_na2[1].length)..-1].sum}\n"
	end
end

module Display

  #def self.display_bleed defender, bleed_log
    #text_color = :light_white
    #back_color = :on_red
    #line = " #{defender.name} takes #{bleed_log.event_data[:bleed_damage]} bleed damage  (#{bleed_log.event_data[:bleed]} bleed)"

    #print " " * 3
    #print (" " * 2).colorize(text_color).send(back_color)
    #print line.colorize(text_color).send(back_color)
    #print (" " * 2).colorize(text_color).send(back_color)
    #print " " * 3
    #print "\n"

    #print Display.draw_dice(bleed_log.event_dice)
  #end

	def self.display_check msg, check
		#@check_sym, @success_mod = check_sym, success_mod
    #check is expected to be <Check>

    width = IO.console.winsize[1]

    line_text = {header: "", top: "", middle: "", bottom: ""}
    write_dice_ascii_to_s(check, line_text)
		line_text[:header] = "#{msg} Check (TN #{check.die_values[:target]})"
		line_text[:header] = "#{line_text[:header][0..-2]}, #{'=' if check.success_mod > 0}#{check.success_mod})" if check.success_mod.to_i != 0

		line_text[:subheader] = "Results #{check.dice_results}"

    print "#{line_text[:header]}\n#{line_text[:subheader]}\n#{line_text[:top]}\n#{line_text[:middle]}\n#{line_text[:bottom]}\n"

    #print Display.draw_dice({msg => check})
    #print "\n"
	end

	def self.display_attack_message attack_log
    #attack_log is expected to be <Attack>
    if attack_log.was_damage_successfull and attack_log.was_attack_successful
			attack_verb = attack_log.notes[:attack_verb]
      text_color = :light_white
      back_color = :on_green
    elsif attack_log.was_damage_successfull == false and attack_log.was_attack_successful
			attack_verb = 'grazed'
      text_color = :light_white
      back_color = :on_red
    else
			attack_verb = 'miss'
      text_color = :light_white
      back_color = :on_red
		end

		line_len = 50
		lines = []
    lines << "#{attack_log.notes[:attacker_name]} #{attack_verb} #{attack_log.notes[:defender_name]} for #{attack_log.damage_value} damage"
  	lines << " ** #{attack_log.notes[:major_damage]} MAJOR DAMAGE **" if attack_log.notes[:major_damage].to_i > 0
  	lines << "#{attack_log.conditions[:bleed]} bleed"
  	lines[-1] << ", #{attack_log.damage_value} damage (#{attack_log.attack_value} roll"
  	lines[-1] << " + #{attack_log.notes[:base_damage]} base"
  	lines[-1] << " - #{attack_log.notes[:damage_reduction]} DR)"

		lines.each do |line|
      print " " * 3
      print (" " * 2).colorize(text_color).send(back_color)
      print line.center(line_len).colorize(text_color).send(back_color)
      print (" " * 2).colorize(text_color).send(back_color)
      print " " * 3
      print "\n"
    end
	end

	def self.get_attack_message message, attack_log
		line_len = 50
  	line1 = " #{message} (#{attack_log.attack_value}) "
  	line2 = "#{attack_log.damage_value.to_s} Damage "
  	line2 << "(#{attack_log.notes[:damage_reduction].to_s} DR), "
  	line2 << "#{attack_log.conditions[:bleed].to_s} bleed"
  	line2 << " ** #{attack_log.notes[:major_damage].to_s} major **" if attack_log.notes[:major_damage].to_i > 0

  	[line1.center(line_len), line2.center(line_len)]
	end

  #def self.display_attack attack_log
    ##attack_log is expected to be <Attack>

		#text_color = :white
    #back_color = :on_black

    #width = IO.console.winsize[1]
    #text = []

    #text = Display.display_attack_message attack_log
    #if attack_log.was_damage_successfull and attack_log.was_attack_successful
      #text_color = :light_white
      #back_color = :on_green
    	#msg = "#{attack_log.notes[:attacker_name]} #{attack_log.notes[:attack_verb]} #{attack_log.notes[:defender_name]}"
    	#text = Display.get_attack_message(msg,attack_log)
    #elsif attack_log.was_attack_successful and attack_log.was_damage_successfull == false
      #text_color = :light_white
      #back_color = :on_red
    	#msg = "#{attack_log.notes[:attacker_name]} #{attack_log.notes[:attack_verb]} #{attack_log.notes[:defender_name]}'s armor"
    	#text = Display.get_attack_message(msg,attack_log)
    #else #Miss
      #text_color = :light_white
      #back_color = :on_red
      ##text << "Miss (#{attack_roll_log.event_data[:success_count]})"
    	#msg = "#{attack_log.notes[:attacker_name]} misses #{attack_log.notes[:defender_name]}"
    	#text = Display.get_attack_message(msg,attack_log)
    #end

		#text.each do |line|
      #print " " * 3
      #print (" " * 2).colorize(text_color).send(back_color)
      #print line.colorize(text_color).send(back_color)
      #print (" " * 2).colorize(text_color).send(back_color)
      #print " " * 3
      #print "\n"
    #end

    #print "\n"

    #print Display.draw_dice(attack_log.rolls)
    #print Display.draw_dice(combat_log.event_dice) if attack_roll_log.event_data[:was_success]
    #print "\n"
  #end

	def self.draw_dice(dice)
  	#dice is expected to be <Hash> containing <Symbols> for keys, and <Roll> for values
  	#<Roll> is expected to have :dice_rolls and :die_values
		#die_values is expected to have die_values[:target] which is expected to hold an integer

    line_text = {header: "", top: "", middle: "", bottom: ""}
    write_dice_ascii_to_s(dice, line_text)

    print "#{line_text[:header]}\n#{line_text[:top]}\n#{line_text[:middle]}\n#{line_text[:bottom]}\n"
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
      #line_text[:header].slice!(-(header_text.length)..-1)
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
