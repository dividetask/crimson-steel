require 'io/console'
require 'colorize'

module Tools
	def self.map2d(a2d, e_code, r_code); a2d.map.with_index { |row, r| r_code.call(row.map.with_index { |e, c| e_code.call(e, r, c) }, r) }; end
	def self.each2d(a2d, e_code, r_code); a2d.each.with_index { |row, r| r_code.call(row.each.with_index { |e, c| e_code.call(e, r, c) }, r) }; end
	def self.pad_array(a2d); return a2d.map { |row| row + Array.new(a2d.map(&:length).max - row.length, '') }; end
	def self.rotate(a2d); return pad_array(a2d).transpose; end
	def self.rotatemap2d(a2d, e_code, r_code); map2d(rotate(a2d), e_code, r_code); end
end

class MenuOptions
  attr_reader :options
	def initialize; reset; end
	def reset; @options = []; end
	#def add(text, action); @options << {text: text, action: action}; "#{(@options.count.to_s.rjust(2)).send(:on_green)} #{text}"; end
	def last_key; (('1'..'9').to_a + ('a'..'z').to_a)[@options.count - 1]; end
	def key_list; (('1'..'9').to_a + ('a'..'z').to_a).first(@options.count); end
	def add(text, action); @options << {text: text, action: action}; "#{('*' + last_key + '*')} #{text}"; end
	def lookup(action); i = key_list.find_index(action); [@options[i][:text], @options[i][:action]] if i; end
end

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

	def display_list(msg_nha2)
		update_width(msg_nha2.values)

		msg_nha2.each do |header, msg_na2|
    	print "#{header}\n#{'═' * msg_na2.map { |msg_a| msg_a.join('').length }.max}\n"
      msg_na2.each { |cols| cols.each.with_index { |msg, c| print msg.send(@col_align[c],@col_width[c]) }; print "\n" }
      print "\n\n"
    end
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

		header_a.each.with_index { |msg,c| print msg.send(@col_align[c],@col_width[c]) }
		print "\n"
		print "#{'═' * @col_width[0..align_na2[0].length-1].sum}#{' ' * @col_width[align_na2[0].length]}#{'═' * @col_width[(-1*align_na2[1].length)..-1].sum}\n"
		msg_na2.each { |row| row.each.with_index { |msg, c| print msg.send(@col_align[c],@col_width[c]) }; print "\n" }
		print "#{'═' * @col_width[0..align_na2[0].length-1].sum}#{' ' * @col_width[align_na2[0].length]}#{'═' * @col_width[(-1*align_na2[1].length)..-1].sum}\n"
	end
end

module Display

  def self.display_character_sheet(char, opt)
    menu = Menu.new(140)
    system('clear')
    menu.display_header(char.name)
    menu.display_section( [ ["Human #{char.klass.to_s.capitalize}", "Level #{char.level}", "Magical Density 1"],
                            ["Combat Pool: #{char.max_combat_pool}", "Perception: #{char.perception}", "Initiative: #{char.initiative}"],
                            ["Damage Reduction: ?", "Damage Resilience: ?", "Speed: ?"],
                            ["Max HP: #{char.max_hp}", "Max Mana: ?", "Mana Regen: ?"] ] )

    attr_display = ATTRIBUTES.map do |attr, name|
      attr_skill = "#{char.attr_dice(attr)}d (TN #{char.attr_tn(attr)})"
      attr_skill += "#{char.attr_bonus(attr)}" if char.attr_bonus(attr) != 0
      attr_save = "#{char.save_dice(attr)}d (TN #{char.save_tn(attr)})"
      attr_save += "#{char.save_bonus(attr)}" if char.save_bonus(attr) != 0
      [opt.add(name, attr), char[attr].to_s, attr_skill, attr_save]
    end

    skill_display = char.skills.select { |skill, skill_p| ![:melee, :ranged].include?(skill) }.map do |skill, skill_p| 
      [opt.add(skill.to_s, skill) , char.ranks(skill).to_s, "#{char.dice(skill)}d (TN #{char.base_tn(skill)})", "-"] 
    end

    [0, (skill_display.count - attr_display.count)].max.times { attr_display << ([''] * attr_display.first.count)}

    menu.display_adjacent_tables(
                            [ [:ljust,          :center, :ljust, :ljust],  [:ljust, :center, :ljust, :center] ],
                            [ ["Attribute",     "Score", "Skill", "Save"], ["Skill", "Ranks", "Dice", "Bonus"] ],
                            [ attr_display, skill_display ] ) 




    attack_display = char.items.map { |item| [item.name, '?', '?', '?', '?', '?', '?', '?'] }

    menu.display_table(
                            [:ljust, :center, :ljust, :center, :center, :center, :center, :ljust],
                            ["Name", "Speed", "Roll", "Atk/Def Bonus", "Dmg Bonus", "Bleed", "MT", "Notes"],
                            attack_display  )

  end

  def self.select_characters(data)
    last_input = nil
    char_hash_list = data.character_list.map { |char| char.role}.uniq.map { |role| [role, data.character_list.select { |char| char.role == role }] }.to_h
    option_array = []
    char_hash_list.each { |role, char_array| char_array.each.with_index { |char, index| option_array << [role, index] } }
    selected_option = 0

    loop do
      menu = Menu.new(80)
      system('clear')

	    lines = char_hash_list.map do |role, char_array|
        char_display = char_array.map.with_index do |char,i|
          icon = ' - '
          icon = ' * ' if [role, i] == option_array[selected_option]
          ["#{icon}#{char.name}", '']
        end
        [role.to_s.capitalize, char_display]
      end
      menu.display_list(lines.to_h)

	    data.status_list.uniq { |status| status.character }.each do |char_status|
      	print "(#{data.status_list.select { |status| status.character == char_status.character }.count}) #{char_status.name}\n"
      end

      STDIN.raw do |io|
        last_input = nil
        input = io.getc
        selected_char = char_hash_list[option_array[selected_option][0]][option_array[selected_option][1]]
        if input == "\e"
          input << io.read_nonblock(2) rescue nil
          case input
          when "\e[A" #up
            selected_option = (option_array.count + selected_option - 1) % option_array.count
          when "\e[B" #down
            selected_option = (selected_option + 1) % option_array.count
          when "\u0003"
            exit
          end
        elsif input == "+"
        	data.status_list << CharacterStatus.new(selected_char)
        elsif input == "-"
          (index = data.status_list.find_index { |status| status.character == selected_char }) && data.status_list.delete_at(index)
        elsif input == "q" || input == "\u0003"
          exit
        else
          last_input = input
        end
      end
    end
  end

  def self.cycle_through_characters(data)
    opt = MenuOptions.new
    char_index = 0
    last_input = nil

    loop do
      opt.reset
      char = data.character_list[char_index]
      display_character_sheet(char, opt)
      if (msg, action = opt.lookup(last_input))
        roll = nil
        if ATTRIBUTES.keys.include? action
          roll = char.attr_roll(action)
          #roll = {(msg + " Check").to_sym => char.attr_roll(action)}
        elsif char.skills.keys.include? action
          roll = char.skill_roll(action)
          #roll = {(msg + " Check").to_sym => char.skill_roll(action)}
        end

        display_check(msg, roll) if roll
      end

      STDIN.raw do |io|
        last_input = nil
        input = io.getc
        if input == "\e"
          input << io.read_nonblock(2) rescue nil
          case input
          when "\e[C" #right
            char_index = (char_index + 1) % data.character_list.count	
          when "\e[D" #left
            char_index = (data.character_list.count + char_index - 1) % data.character_list.count	
          when "\u0003"
            exit
          #when "\e[A" #up
          #when "\e[B" #down
          end
        elsif input == "q" || input == "\u0003"
          exit
        else
          last_input = input
        end
      end
    end
  end

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
