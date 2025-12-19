

#class NewDisplay
  #attr_reader :data, :option_hash

	#def initialize(data); @data = data; @option_hash = nil; end
  ##def main_menu; menu [:change_monsters, :view_characters, :roll_initiative, :view_combat]; end
  #def main_menu; menu [:change_monsters]; end
	#def press_any_key; puts "Press Enter to continue..."; gets; end

  #def menu(menu_data)
    #input = nil
    #option_list = (menu_data.class == Array) ? menu_data.map { |func_sym| [func_sym] } : menu_data.to_a
    #while (true)
      #system('clear')
      #option_list.each.with_index { |func_data, index| print "#{index + 1}. #{Tools.humanize(func_data[0])}\n" }
      #input = gets.chomp
      #break if input == 'q'
      #input = input.to_i
      #send(option_list[input - 1][0], *option_list[input - 1][1..-1]) if ( (input > 0) and (input <= option_list.count) )
    #end
  #end

  #def display_char_nha char_nha, selected_char
    #menu = Menu.new(80)
    #system('clear')

    #lines = char_nha.map do |group_name, char_list|
      #char_display = char_list.map do |char|
        #letter = @option_hash.invert[char]
        #["#{'* ' if selected_char == char}#{letter}. #{char.name}", '']
      #end
      #[group_name.to_s.capitalize, char_display]
    #end
    #menu.display_list(lines.to_h)

    #@data.status_list.uniq { |status| status.character }.each do |char_status|
      #print "(#{@data.status_list.select { |status| status.character == char_status.character }.count}) #{char_status.name}\n"
    #end
  #end

  #def get_keypress
    #input = nil
    #begin
      #STDIN.raw do |io|
        #input = io.getc
        #if KEYCODES[input]
          #input = KEYCODES[input]
        #elsif input == "\e"
          #input << io.read_nonblock(2) rescue nil
          #input = KEYCODES[input]
        #elsif input == 'q'
          #input = :exit
        #end
        #break
      #end
    #ensure
      #system('stty sane')
    #end
    #return input
  #end

  #def change_monsters
    #char_nha = @data.character_list.map { |char| char.role}.uniq.map { |role| [role, @data.character_list.select { |char| char.role == role }] }.to_h

    #@option_hash = {}
		#alphabet = ('a'..'z').to_a
    #char_nha.each { |role, char_list| char_list.each { |char| letter = alphabet.shift; @option_hash[letter] = char } }

    #selected_char, input = nil
    #while (input != :exit) and (input != 'q')
      #display_char_nha char_nha, selected_char
      #input = get_keypress

      #if @option_hash[input].class == CharacterSheet
        #selected_char = @option_hash[input]
      #elsif input == "+" and selected_char != nil
        #new_char =  CharacterStatus.new(selected_char)
        #if @data.status_list.select { |status| status.character == new_char.character }.count == 0
          #new_char.set_mob_index(nil)
        #else
          #new_char_index = 0
          #@data.status_list.each { |status| status.set_mob_index(++new_char_index) }
          #new_char.set_mob_index(new_char_index)
        #end
        #@data.status_list << new_char
      #elsif input == "-" and selected_char != nil
        #(index = @data.status_list.find_index { |status| status.character == selected_char }) && @data.status_list.delete_at(index)
      #elsif input == :exit
        #break
      #end
    #end



    #while (input != 'q')
      #display_char_nha char_nha, selected_char
      #input = gets.chomp
      #selected_char = @option_hash[input] if @option_hash.keys.include? input and @option_hash[input].class == CharacterSheet
      #@data.status_list
      #if input == "+"
        #new_char =  CharacterStatus.new(selected_char)
        #if data.status_list.select { |status| status.character == new_char.character }.count == 0
          #new_char.set_mob_index(nil)
        #else
          #new_char_index = 0
          #data.status_list.each { |status| status.set_mob_index(++new_char_index) }
          #new_char.set_mob_index(new_char_index)
        #end
        #data.status_list << new_char
      #elsif input == "-"
        #(index = data.status_list.find_index { |status| status.character == selected_char }) && data.status_list.delete_at(index)
      #end
    #end
  #end

  #def self.select_characters(data)
    #system('clear')
    #last_input = nil
    #char_hash_list = data.character_list.map { |char| char.role}.uniq.map { |role| [role, data.character_list.select { |char| char.role == role }] }.to_h
    #option_array = []
    #char_hash_list.each { |role, char_array| char_array.each.with_index { |char, index| option_array << [role, index] } }
    #selected_option = 0

    #input = nil
    #while (input != 'q')
      #menu = Menu.new(80)
      #system('clear')

	    #lines = char_hash_list.map do |role, char_array|
        #char_display = char_array.map.with_index do |char,i|
          #icon = ' - '
          #icon = ' * ' if [role, i] == option_array[selected_option]
          #["#{icon}#{char.name}", '']
        #end
        #[role.to_s.capitalize, char_display]
      #end
      #menu.display_list(lines.to_h)

	    #data.status_list.uniq { |status| status.character }.each do |char_status|
      	#print "(#{data.status_list.select { |status| status.character == char_status.character }.count}) #{char_status.name}\n"
      #end

      #STDIN.raw do |io|
        #last_input = nil
        #input = io.getc
        #selected_char = char_hash_list[option_array[selected_option][0]][option_array[selected_option][1]]
        #if input == "\e"
          #input << io.read_nonblock(2) rescue nil
          #case input
          #when "\e[A" #up
            #selected_option = (option_array.count + selected_option - 1) % option_array.count
          #when "\e[B" #down
            #selected_option = (selected_option + 1) % option_array.count
          #when "\u0003"
            #exit
          #end
        #elsif input == "+"
        	#new_char =  CharacterStatus.new(selected_char)
					#if data.status_list.select { |status| status.character == new_char.character }.count == 0
						#new_char.set_mob_index(nil)
					#else
						#new_char_index = 0
						#data.status_list.each { |status| status.set_mob_index(++new_char_index) }
						#new_char.set_mob_index(new_char_index)
					#end
					#data.status_list << new_char
        #elsif input == "-"
          #(index = data.status_list.find_index { |status| status.character == selected_char }) && data.status_list.delete_at(index)
        #elsif input == "\u0003"
          #exit
        #else
          #last_input = input
        #end
      #end
    #end
    #data.save
  #end
#end


module DisplayOld
  def self.main_menu(data)

    input = nil
    while (input != 'q')
      system('clear')

      print "1. Select Characters\n"
      print "2. View Character Sheets\n"
      print "3. Roll Initiative\n"
      print "4. Handle Combat\n"

      input = gets.chomp

      if input == '1'
        select_characters(data)
      elsif input == '2'
        cycle_through_characters(data)
      elsif input == '3'
        handle_initiative(data)
      elsif input == '4'
        display_combat(data)
      end
    end
  end

  def self.handle_initiative(data)
    menu = Menu.new(140)
    system('clear')
    menu.display_header('Combat')

    input = nil
    while (input != 'q')
      system('clear')

			data.status_list ||= []
			data.initiative ||= []
      init_found = data.status_list.map { |status| data.initiative.any? { |init_roll| init_roll.character == status.character } }.any?

			if data.status_list == []
				break
			elsif init_found
				display_init(data)
        print "\n\n"
      elsif data.initiative and data.initiative.count > 0
        print "Initiative doesn't match characters\n\n"
      end
			
      print "1. Manually input character rolls\n"
      print "2. Roll for everyone\n"
      print "q. Quit\n" 

      input = gets.chomp

      if input == '1'
        npc_rolls = InitiativeRoll.roll(data.status_list.select { |status| status.role != :PC })
        npc_rolls.each { |init_roll| print "#{init_roll.character.name} rolled #{init_roll.to_s}\n" }
        pc_rolls = data.status_list.select { |status| status.role == :PC }.map do |status|
          print "\nPlease input #{status.name}'s roll: "
          input = gets.chomp
					InitiativeRoll.roll_manual(status, input)
        end
        data.initiative = InitiativeRoll.sort(pc_rolls + npc_rolls)
				data.save
      elsif input == '2'
        data.initiative = InitiativeRoll.roll(data.status_list)
				data.save
      end
    end
  end

	def self.display_init(data)
    menu = Menu.new(80)
    lines = []
    lines << [ "Init", "Name" ]
    data.initiative.each do |init|
			mob_count = data.status_list.select { |status| status.character == init.character }.count
			lines << [init.to_s, "#{init.character.name}#{" x#{mob_count}" if mob_count > 1}"]
		end
    menu.display_section lines
	end

  def self.choose_defense_weapon(active_char)
		print "Choose defense weapon\n"
		weapons = ('a'..'z').to_a.zip(active_char.items.select { |item| [:weapon, :shield].include? item.category }).to_h.compact
		weapons.each { |letter, weapon| print "#{letter}. #{weapon.name}\n" }

		weapon_choice = gets.chomp
		return weapons[weapon_choice] if weapons.keys.include?(weapon_choice)
	end

  def self.choose_weapon(data, active_char)
		print "Choose weapon\n"
		weapons = ('a'..'z').to_a.zip(active_char.items.select { |item| item.category == :weapon }).to_h.compact
		weapons.each { |letter, weapon| print "#{letter}. #{weapon.name}\n" }

		weapon_choice = gets.chomp
		return weapons[weapon_choice] if weapons.keys.include?(weapon_choice)
	end

  def self.choose_enemy(data, active_char)
		print "Choose target\n"
		enemies = ('a'..'z').to_a.zip(data.status_list.select { |status| status.role != active_char.role }).to_h.compact
		enemies.each { |letter, target| print "#{letter}. #{target.get_name}\n" }

		target_choice = gets.chomp
		return enemies[target_choice] if enemies.keys.include?(target_choice)
	end

  def self.how_many_dice(data, active_char)
		print "How many dice (min 2, max #{active_char.attack_dice})?\n"
		return gets.chomp
	end

  def self.how_many_dodge_dice(data, target)
		print "How many dodge dice for #{target.get_name}?\n"
		return gets.chomp
	end

	def self.display_combat_header(data)
    menu = Menu.new(140)
    system('clear')
    menu.display_header('Combat')
    lines = []
    lines << [ "Init", "Name", "HP", "Afflictions", "Combat Dice"]
    data.initiative.each do |init|
      status_info = [init.to_s]
      data.status_list.select { |status| status.character == init.character }.each do |status|
        status_info << status.name
        status_info << "#{status.get_remaining_hp}/#{status.max_hp}"
        status_info << "bleed: #{status.health_notes[:bleed]}"
        status_info << "#{status.combat_pool[:remaining]}/#{status.combat_pool[:maximum]}"
        lines << status_info.dup
        status_info = ['']
      end
    end
    menu.display_section_set_width lines, [10]
    return menu
  end

  def self.combat(data)
		handle_initiative(data)

		input = nil
		while (input != 'q')
			menu = Menu.new(140)
			system('clear')
			menu.display_header('Combat')
			active_char = nil

			lines = []
			lines << [ "Init", "Name", "HP", "Afflictions", "Combat Dice"]
			data.initiative.each do |init|
				status_info = [init.to_s]
				data.status_list.select { |status| status.character == init.character }.each do |status|
					active_char = status if active_char == nil and status.turn_complete? == false

					status_info << status.name
					status_info << "#{status.get_remaining_hp}/#{status.max_hp}"
					status_info << "bleed: #{status.health_notes[:bleed]}"
					status_info << "#{status.combat_pool[:remaining]}/#{status.combat_pool[:maximum]}"
					lines << status_info.dup
					status_info = ['']
				end
			end
			if active_char == nil
				data.status_list.each do |status|
					status.new_initiative
					active_char = status if active_char == nil and status.character == data.initiative.first.character
				end
			end

			menu.display_section_set_width lines, [10]

			print "\n\n#{active_char.name}'s turn\n\n"
			
			print "1. Attack\n"
			print "2. Spell/Ability\n"
			print "3. Move\n"
			print "4. Bonus Action\n"
			print "5. End Turn\n"
			print "q. Exit Combat\n\n"

			input = gets.chomp

			if input == '1'
				begin
					print "press q to finish attacks\n"
					weapon = choose_weapon(data, active_char)
					break unless weapon
					target_char = choose_enemy(data, active_char)
					break unless target_char
					attack_dice_count = how_many_dice(data, active_char).to_i
					break unless attack_dice_count.to_i > 0
					dodge_dice_count = how_many_dodge_dice(data, target_char).to_i

					tn = active_char.attack_base_tn(weapon)
					success_mod = active_char.attack_bonus(weapon)
					if dodge_dice_count > 0
						defense_weapon = choose_defense_weapon(target_char)
            defense_tn_mod = target_char.attack_tn_mod(defense_weapon)
            binding.irb
            print "Attacker Bonus: #{tn}, Defender Bonus: #{defense_tn_mod}"
						tn -= defense_tn_mod
          elsif target_char.klass != :barbarian
            print "Attacker Bonus: #{tn}, Flatfooted -2"
            tn -= 2
          else
            print "Attacker Bonus: #{tn}"
					end
					success_mod += [0, 4 - tn].max
					success_mod -= [0, tn - 9].max
					tn = [4,[9, tn].min].max

					print ", success mod: #{success_mod}\n"
					print "How many successes [TN: #{tn}, success mod: #{success_mod}] ('r' to roll)\n"
					success_count = gets.chomp.to_i

					loop if success_count < 2

					target_char.take_action(BONUS_ACTION, dodge_dice_count) if dodge_dice_count > 0
					active_char.spend_dice(attack_dice_count)

					damage = success_count + weapon.get_base_weapon_damage(active_char)
					damage -= target_char.get_dr(active_char)

					minor_damage = [damage, target_char.get_resiliance].min
					moderate_damage = [[damage - minor_damage, 0].max, weapon.get_threshold].min
					major_damage = [damage - minor_damage - moderate_damage, 0].max

					target_char.add_damage(Damage.new(nil, MINOR_DAMAGE, minor_damage)) if minor_damage > 0
					target_char.add_damage(Damage.new(nil, MODERATE_DAMAGE, moderate_damage)) if moderate_damage > 0
					target_char.add_damage(Damage.new(nil, MAJOR_DAMAGE, major_damage)) if major_damage > 0

					print "How much bonus damage\n"
					bonus_damage = gets.chomp.to_i
					target_char.add_damage(Damage.new(nil, MODERATE_DAMAGE, bonus_damage)) if bonus_damage > 0
					target_char.update_bleed(weapon.get_bleed_mod + damage)
				end while (true)
				active_char.take_action(MAIN_ACTION, 0)
			elsif input == '2'
				print 'Not implemented yet\n'
			elsif input == '3' #move
				active_char.take_action(MOVE_ACTION)
			elsif input == '4'
				dice_spent = gets.chomp
				active_char.take_action(BONUS_ACTION, dice_spent.to_i) if dice_spent.to_i > 0
			elsif input == '5'
				active_char.end_turn
				active_char = nil
			end
			data.save
		end
  end
	

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

    skill_display = char.skills.select { |skill, skill_p| ![:bab].include?(skill) }.map do |skill, skill_p| 
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
    system('clear')
    last_input = nil
    char_hash_list = data.character_list.map { |char| char.role}.uniq.map { |role| [role, data.character_list.select { |char| char.role == role }] }.to_h
    option_array = []
    char_hash_list.each { |role, char_array| char_array.each.with_index { |char, index| option_array << [role, index] } }
    selected_option = 0

    input = nil
    while (input != 'q')
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
        	new_char =  CharacterStatus.new(selected_char)
					if data.status_list.select { |status| status.character == new_char.character }.count == 0
						new_char.set_mob_index(nil)
					else
						new_char_index = 0
						data.status_list.each { |status| status.set_mob_index(++new_char_index) }
						new_char.set_mob_index(new_char_index)
					end
					data.status_list << new_char
        elsif input == "-"
          (index = data.status_list.find_index { |status| status.character == selected_char }) && data.status_list.delete_at(index)
        elsif input == "\u0003"
          exit
        else
          last_input = input
        end
      end
    end
    data.save
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
































class Damage < Serializable
  attr_reader :damage_type, :damage_severity, :damage_amount
	#damage_severity: 0 - none, 1 - minor, 2 - moderate, 3 - major
  def initialize(dt, ds, da); @damage_type, @damage_severity, @damage_amount = dt, ds, da; end
	def get_pain; return @damage_type == 3 ? @damage_amount * 2 : 0; end
end

class Attack < Serializable
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

module TestStuff2
	@char, @skill, @attr = nil

  def self.quarter_mod(char, attr); return char[attr] / 4; end
  def self.method_missing(method, *args)
binding.irb
	end
  def self.method_added(method_name)
    return if @wrapping  # Prevent infinite recursion
binding.irb
    
    original_method = method(method_name)
    params = original_method.parameters.map { |_, name| name }
    
    @wrapping = true
    define_singleton_method(method_name) do |*args|
      # Set instance variables from parameter names
      params.each_with_index do |param_name, i|
        instance_variable_set("@#{param_name}", args[i])
      end
      
      # Call private version
      send("private_#{method_name}")
    end
    @wrapping = false
  end
end

module TestStuff3
  @char, @skill, @attr = nil
  
def self.singleton_method_added(method_name)
  return if @wrapping
  return if method_name == :singleton_method_added
  return if method_name.to_s.start_with?('private_')
  
  original_method = method(method_name)
  params = original_method.parameters.map { |_, name| name }
  
  @wrapping = true
binding.irb
  define_singleton_method(method_name) do |*args|
    params.each_with_index { |param_name, i| instance_variable_set("@#{param_name}", args[i]) }
    send("private_#{method_name}")
  end
  @wrapping = false
end
  
  def self.quarter_mod(char, attr); end
  def self.skill_ranks(char, skill); end
  
  private
  
  def self.private_quarter_mod
    @char[@attr] / 4
  end
  
  def self.private_skill_ranks
    # implementation
  end
end






class DataStore
	attr_accessor :character_list

	def initialize(filename)
		@filename = "#{filename.to_s}.json"
		if File.exist?(@filename)
			data = JSON.parse(File.read(@filename))
			data.each do |key, value|
				instance_variable_set("@#{key}", Serializable.deserialize_value(value))
			end
		else
			@character_list = []
		end
	end

	def save
		data = instance_variables.reject { |v| v == :@filename }.map do |v|
			[v.to_s.delete('@'), Serializable.serialize_value(instance_variable_get(v))]
		end.to_h
		File.write(@filename, JSON.pretty_generate(data))
	end
end

class Serializable

  def self.serialize_value(value)
    case value
    when Symbol
      {'_type' => 'symbol', '_value' => value.to_s}
    when Serializable
      {'_class' => value.class.name, '_data' => value.to_hash_for_datastore}
    when Hash
			# Serialize both keys and values, store as array of [key, value] pairs
			serialized_pairs = value.map { |k, v| [serialize_value(k), serialize_value(v)] }
			{'_type' => 'hash', '_pairs' => serialized_pairs}
    when Array
      value.map { |item| serialize_value(item) }
    when String, Numeric, TrueClass, FalseClass, NilClass
      value
    else
      value.to_s
    end
  end

	def self.deserialize_value(value)
		case value
		when Hash
			if value['_type'] == 'symbol'
				value['_value'].to_sym
			elsif value['_type'] == 'hash'
				# Reconstruct hash from [key, value] pairs
				result = {}
				value['_pairs'].each do |k, v|
					result[deserialize_value(k)] = deserialize_value(v)
				end
				result
			elsif value['_class']
				Object.const_get(value['_class']).from_hash(value['_data'])
			else
				# Plain hash, deserialize values only
				value.transform_values { |v| deserialize_value(v) }
			end
		when Array
			value.map { |item| deserialize_value(item) }
		else
			value
		end
	end

  def self.from_hash(data)
    obj = allocate
    data.each { |k, v| obj.instance_variable_set("@#{k}", deserialize_value(v)) }
    obj
  end

  def to_hash_for_datastore
    instance_variables.map { |v| [v.to_s.delete('@'), self.class.serialize_value(instance_variable_get(v))] }.to_h
  end
end


def character_creation_menu(data)
	if data.character_list && !data.character_list.empty?
		olga = data.character_list.first
		name = olga.name
		gender = olga.gender
		character_type = olga.character_sheet.character_type
		character_class = olga.character_sheet.character_class
		level = olga.character_sheet.level
		str = olga.character_sheet.str
		dex = olga.character_sheet.dex
		con = olga.character_sheet.con
		int = olga.character_sheet.int
		wis = olga.character_sheet.wis
		cha = olga.character_sheet.cha
		skills = olga.character_sheet.skills
	else
		name = "Olga"
		gender = Gender.f
		character_type = :PC
		character_class = :barbarian
		level = 3
		str, dex, con, int, wis, cha = 16, 14, 16, 10, 12, 9
		skills = {melee: 3, ranged: 2}
	end
  
  loop do
    system('clear')
    puts "=== Character Creator ==="
    puts "1. Name: #{name}"
    puts "2. Gender: #{gender.to_s}"
    puts "3. Type: #{character_type}"
    puts "4. Class: #{character_class}"
    puts "5. Level: #{level}"
    puts "6. STR: #{str}"
    puts "7. DEX: #{dex}"
    puts "8. CON: #{con}"
    puts "9. INT: #{int}"
    puts "10. WIS: #{wis}"
    puts "11. CHA: #{cha}"
    puts "12. Skills: #{skills}"
    puts "13. Save and Exit"
    puts "14. Cancel"
    print "\nSelect option: "
    
    choice = gets.chomp.to_i
    
    case choice
    when 1 then (print "Name: "; name = gets.chomp)
		when 2 then (print "Gender (m/f): "; input = gets.chomp.downcase; gender = input == 'm' ? Gender.m : input == 'f' ? Gender.f : gender)
    when 3 then (print "Type: "; character_type = gets.chomp.to_sym)
    when 4 then (print "Class: "; character_class = gets.chomp.to_sym)
    when 5 then (print "Level: "; level = gets.chomp.to_i)
    when 6 then (print "STR: "; str = gets.chomp.to_i)
    when 7 then (print "DEX: "; dex = gets.chomp.to_i)
    when 8 then (print "CON: "; con = gets.chomp.to_i)
    when 9 then (print "INT: "; int = gets.chomp.to_i)
    when 10 then (print "WIS: "; wis = gets.chomp.to_i)
    when 11 then (print "CHA: "; cha = gets.chomp.to_i)
    when 12 then (print "Skills (e.g., melee:3,ranged:2): "; skills = gets.chomp.split(',').map { |s| k,v = s.split(':'); [k.to_sym, v.to_i] }.to_h)
    when 13
      stats = CharacterStats.new(character_type, character_class, level, str, dex, con, int, wis, cha, skills)
      char = Character.new(name, gender, stats, [])
      data.character_list ||= []
			existing_index = data.character_list.find_index { |c| c.name == name }
			if existing_index
				data.character_list[existing_index] = character
			else
				data.character_list << character
			end
      data.save
      puts "Character saved!"
      break
    when 14
      puts "Cancelled"
      break
    end
  end
end

data = DataStore.new('campaign')
character_creation_menu(data)

