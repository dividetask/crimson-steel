require 'io/console'
require 'colorize'
KEYCODES = {"\e[A" => :up , "\e[B" => :down, "\e[C" => :right, "\e[D" => :left, "\u0003" => :exit}

module Tools
	def self.map2d(a2d, e_code, r_code); a2d.map.with_index { |row, r| r_code.call(row.map.with_index { |e, c| e_code.call(e, r, c) }, r) }; end
	def self.each2d(a2d, e_code, r_code); a2d.each.with_index { |row, r| r_code.call(row.each.with_index { |e, c| e_code.call(e, r, c) }, r) }; end
	def self.pad_array(a2d); return a2d.map { |row| row + Array.new(a2d.map(&:length).max - row.length, '') }; end
	def self.rotate(a2d); return pad_array(a2d).transpose; end
	def self.rotatemap2d(a2d, e_code, r_code); map2d(rotate(a2d), e_code, r_code); end
  def self.humanize(sym); return sym.to_s.tr('_', ' ').capitalize; end
	def self.press_any_key; puts "Press Enter to continue..."; gets; end
	def self.number_with_plus(num); return "#{'+' if num >= 0}#{num}"; end

  def self.get_keypress
    input = nil
    begin
      STDIN.raw do |io|
        input = io.getc
        if KEYCODES[input]
          input = KEYCODES[input]
        elsif input == "\e"
          input << io.read_nonblock(2) rescue nil
          input = KEYCODES[input]
        end
        break
      end
    ensure
      system('stty sane')
    end
    return input
  end
end

class Display
  attr_reader :width, :col_width, :col_align
	def initialize(width); reset(width); end
  def reset(width); system('clear'); change_width(width); end
  def change_width(width); @width = width; @col_width = [nil]; @col_align = [nil]; end
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

	def display_section_set_width(msg_na2, width_overides)
		update_width(msg_na2)
		width_overides.each_with_index { |new_width,index| @col_width[index] = new_width if new_width}
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

  def display_selectable_list(header, items, selected_index, item_columns)
    # items: array of hashes with column data
    # item_columns: array of column names to display
    # selected_index: index of currently selected item
    
    display_header(header) if header
    
    lines = []
    lines << ["", *item_columns]
    
    items.each_with_index do |item, index|
      selector = (index == selected_index) ? ">" : " "
      row = [selector]
      item_columns.each { |col| row << item[col].to_s }
      lines << row
    end
    
    display_section lines
  end
  
  def display_option_menu(title, options)
    # options: array of strings or hash of {key => description}
    print "\n#{title}\n" if title
    print "=" * (title ? title.length : 50) + "\n"
    
    if options.is_a?(Array)
      options.each_with_index { |option, idx| print "#{idx + 1}. #{option}\n" }
    elsif options.is_a?(Hash)
      options.each { |key, desc| print "#{key}. #{desc}\n" }
    end
  end
end

class Menu
  include MenuSelectMonsters
	include MenuCommonFunctions
  include MenuInitiative
  include MenuCombat
	include MenuManual

  attr_reader :display_obj, :data, :option_hash

	def initialize(data); @display_obj, @option_hash = nil; @data = data; end
  def main_menu; menu [:change_monsters, :roll_initiative, :manualy_manage_resources]; end
  #def main_menu; menu [:change_monsters, :roll_initiative, :combat]; end
  ##def main_menu; menu [:change_monsters, :view_characters, :roll_initiative, :view_combat]; end

  def get_number(message, accepted_number_list, default_val = nil)
    input = nil
    while (true)
      print "#{message} "
      input = gets.chomp
      break if input == 'q'
      return default_val if default_val and input == ''
      input = input.to_i
      break if accepted_number_list.include? input
    end
    input
  end

  def get_menu_selection message, option_hash = nil
		@option_hash = option_hash if option_hash
    input = nil
    while (true)
      print "#{message}\n"
      @option_hash.each { |letter, desc| print "#{letter}. #{desc}\n" }
      input = gets.chomp
      break if input == 'q'
      input = input.to_i if input.to_i > 0 and @option_hash[input.to_i]
      break if @option_hash[input]
    end
    input
  end

  def menu(menu_data, clear_screen = true)
    input = nil
    option_list = (menu_data.class == Array) ? menu_data.map { |func_sym| [func_sym] } : menu_data.to_a
    while (true)
      system('clear') if clear_screen
      option_list.each.with_index { |func_data, index| print "#{index + 1}. #{Tools.humanize(func_data[0])}\n" }
      input = gets.chomp
      break if input == 'q'
      input = input.to_i
      send(option_list[input - 1][0], *option_list[input - 1][1..-1]) if ( (input > 0) and (input <= option_list.count) )
    end
  end

  def navigate_list_with_menu(items, item_columns, header, menu_builder_proc)
    # items: array of objects to display
    # item_columns: hash of {column_name: proc} to extract data from items
    # header: string for display header
    # menu_builder_proc: proc that takes selected item and returns options array/hash
    
    selected_index = 0
    input = nil
    
    while (input != 'q')
      @display_obj == nil ? @display_obj = Display.new(140) : @display_obj.reset(140)
      
      # Build display data
      display_items = items.map do |item|
        item_columns.transform_values { |proc| proc.call(item) }
      end
      
      @display_obj.display_selectable_list(header, display_items, selected_index, item_columns.keys)
      
      # Build and display menu for selected item
      selected_item = items[selected_index]
      options = menu_builder_proc.call(selected_item)
      @display_obj.display_option_menu("#{selected_item.name rescue 'Selected Item'} - Actions", options)
      
      print "\nArrow Keys: Navigate | Number/Letter: Select Action | Q: Quit\n"
      
      input = Tools.get_keypress
      
      case input
      when :up
        selected_index = (selected_index - 1) % items.length
      when :down
        selected_index = (selected_index + 1) % items.length
      when :exit
        break
      else
        yield(selected_item, input, options) if block_given?
      end
    end
  end
end

module MenuManual
  def manualy_manage_resources
    item_columns = {
      "Init" => ->(char) { @data.initiative.find { |init| init.character == char.character }&.to_s || "" },
      "Name" => ->(char) { char.name },
      "HP" => ->(char) { "#{char.get_remaining_hp}/#{char.max_hp}" },
      "Mana" => ->(char) { "#{char.get_remaining_mana}/#{char.max_mana}" },
      "Dice" => ->(char) { "#{char.combat_pool[:remaining]}/#{char.combat_pool[:maximum]}" },
      "Bleed" => ->(char) { "#{char.health_notes[:bleed]}" },
      "Minor" => ->(char) { "#{char.get_damage(MINOR_DAMAGE)}" },
      "Major" => ->(char) { "#{char.get_damage(MAJOR_DAMAGE)}" },
      "Saturation" => ->(char) { "#{char.get_saturation}/#{char.cha}" }
    }
    
    # Sort status_list by initiative order
    sorted_status_list = @data.status_list.sort_by do |status|
      @data.initiative.index { |init| init.character == status.character } || 9999
    end
    
    menu_builder = ->(char) do
      options = []
      char.weapons.each { |weapon| options << "Attack/Parry with #{weapon.name}" }
			char.items.select { |item| item.category == :shield }.each { |shield| options << "Block with #{shield.name}" }

      options += ["Dodge", "Take Damage", "Spend Mana", "Use Action Dice", "Cure Lesser Wounds", "Cure Simple Wounds", "Afflictions", "Add Saturation", "New Round" ]
      options
    end
    
    navigate_list_with_menu(sorted_status_list, item_columns, "Manage Resources", menu_builder) do |char, input, options|
      if input.to_i > 0 && input.to_i <= options.length
        handle_resource_action(char, input.to_i, options)
      end
    end
  end

  def handle_resource_action(char, action_num, options)
    weapon_count = char.weapons.length
		shield_list = char.items.select { |item| item.category == :shield }
    
    if action_num <= weapon_count
      # Handle weapon attack
      weapon = char.weapons[action_num - 1]
      attack_bonus = char.attack_bonus(weapon)
      attack_bonus_string = "#{'+' if attack_bonus >= 0}#{attack_bonus}"
      
      attack_dice = get_number("Attack Bonus #{attack_bonus_string}, How many attack dice (2-#{char.attack_dice}), Speed #{weapon.speed}", (0..char.attack_dice).to_a)
      return if attack_dice == 'q'

			if weapon.class != ConjuredEquipment or weapon.needs_dice?
				char.spend_dice(attack_dice + weapon.speed)
				print "#{char.name} spent #{attack_dice + weapon.speed} dice (#{attack_dice} attack + #{weapon.speed} weapon speed)\n"
			else
				print "#{char.name} spent 0 dice, this spell costs zero dice\n"
			end
    elsif action_num <= weapon_count + shield_list.length
      # Handle shield
      shield = shield_list[action_num - 1 - weapon_count]
      attack_bonus = char.attack_bonus(shield)
      attack_bonus_string = "#{'+' if attack_bonus >= 0}#{attack_bonus}"
      
      attack_dice = get_number("Defense Bonus #{attack_bonus_string}, How many block dice (2-#{char.attack_dice})", (0..char.attack_dice).to_a)
      return if attack_dice == 'q'

			if shield.class != ConjuredEquipment or shield.needs_dice?
				char.spend_dice(attack_dice)
				print "#{char.name} spent #{attack_dice} dice\n"
			else
				print "#{char.name} spent 0 dice, this spell costs zero dice\n"
			end
    elsif options[action_num -1] == "Dodge"
      attack_bonus = char.attr_bonus(:dex)
      attack_bonus_string = "#{'+' if attack_bonus >= 0}#{attack_bonus}"
      attack_dice = get_number("Defense Bonus #{attack_bonus_string}, How many dodge dice (2-#{char.attr_dice(:dex)})", (0..char.attr_dice(:dex)).to_a)
      return if attack_dice == 'q'

			char.spend_dice(attack_dice)
			print "#{char.name} spent #{attack_dice} dice\n"
    elsif options[action_num -1] == "Take Damage"
      initial_damage = get_number("How much damage?", (0..100).to_a)
      dr = get_number("How much damage reduction?  #{char.get_base_dr()}", (0..100).to_a, char.get_base_dr())
      minor = get_number("How much minor damage? Resiliance #{char.get_resiliance}", (0..100).to_a, char.get_resiliance)
      major = get_number("How much major damage? #{initial_damage-dr-minor} remaining", (0..100).to_a, initial_damage-dr-minor)
      moderate = get_number("How much moderate damage? #{initial_damage-dr-minor-major}", (0..100).to_a, initial_damage-dr-minor-major)
      bonus = get_number("How much bonus damage?", (0..100).to_a, 0)
      bleed = get_number("How much bleed? #{initial_damage-dr+5}", (-100..100).to_a, initial_damage-dr+5)

			char.add_damage(Damage.new(:physical, MINOR_DAMAGE, minor)) if minor > 0
			char.add_damage(Damage.new(:physical, MODERATE_DAMAGE, moderate)) if moderate > 0
			char.add_damage(Damage.new(:physical, MAJOR_DAMAGE, major)) if major > 0
			char.add_damage(Damage.new(:bonus, MODERATE_DAMAGE, bonus)) if bonus > 0
			char.update_bleed(bleed)

      # Handle other actions
    elsif options[action_num -1] == "Spend Mana"
      mana = get_number("How much mana?", (-100..100).to_a)
			char.spend_mana(mana.to_i) if mana.to_i != 0
    elsif options[action_num -1] == "Use Action Dice"
      attack_dice = get_number("How many dice?", (0..100).to_a)
      return if attack_dice == 'q'

			char.spend_dice(attack_dice)
			print "#{char.name} spent #{attack_dice} dice\n"
      #options += ["Dodge", "Take Damage", "Spend Mana", "Use Action Dice",  ]
    #elsif ["Cure Lesser Wounds", "Cure Simple Wounds"].include? options[action_num -1]
    elsif options[action_num -1] == "Cure Lesser Wounds"
			char.cure_damage(4, MINOR_DAMAGE)
			char.cure_damage(2, MODERATE_DAMAGE)
      sat = get_number("How much saturation (#{5-char.density})?", (2..5).to_a, (5-char.density))
			char.add_mana_saturation(sat.to_i) if sat.to_i != 0
    elsif options[action_num -1] == "Cure Simple Wounds"
			char.cure_damage(8, MINOR_DAMAGE)
			char.cure_damage(4, MODERATE_DAMAGE)
      sat = get_number("How much saturation (#{10-char.density})?", (3..10).to_a, (10-char.density))
			char.add_mana_saturation(sat.to_i) if sat.to_i != 0
    elsif options[action_num -1] == "Add Saturation"
      sat = get_number("How much saturation?", (0..50).to_a)
			char.add_mana_saturation(sat.to_i) if sat.to_i != 0
    elsif options[action_num -1] == "New Round"
			@data.status_list.each { |status| status.new_initiative }
    elsif options[action_num -1] == "Afflictions"
			default_bleed = 1 + (char.health_notes[:bleed].to_i/10)
      bleed = get_number("How much bleed (#{default_bleed})?", (0..50).to_a, default_bleed)
			char.add_damage(Damage.new(:bleed, MINOR_DAMAGE, bleed.to_i)) if bleed.to_i > 0
    end
		@data.save
		#binding.irb if options[action_num -1] == "Take Damage"
    Tools.press_any_key
  end
end


    #input = nil
		#selected = 0
    #while (input != 'q')
			#display_array = [[], []]
			#@data.status_list.each.with_index { |char, index| display_array[0][index] = "#{index == selected ? '*' : ' '}  #{char.name}" }

			#weapon_options = ('a'..'z').to_a.zip(@data.status_list[selected].weapons)
			#weapon_options.each.with_index { |weapon_w_letter, index| display_array[1][index] = "#{weapon_w_letter[0]}. #{weapon_w_letter[1].name if weapon_w_letter[1]}" }

			#display_array.each do |row|
				#print "#{row[0]}   #{row[1]}\n"
			#end
      #input = Tools.get_keypress
		#end
	#end
#end



		#@option_hash = weapon_options.map { |letter, weapon| [letter, weapon.name] }.to_h
  	#weapon_key = get_menu_selection "Choose weapon"
		#return weapon_options[weapon_key] if weapon_options[weapon_key]

		#enemy_list = @data.status_list.select { |c| c.role != attacker.role }
  	#enemy_options = ('a'..'z').to_a.zip(enemy_list).to_h.compact
		#@option_hash = enemy_options.map { |letter, enemy| [letter, enemy.name] }.to_h
		#enemy_key = get_menu_selection "Choose target"
		#return enemy_options[enemy_key] if enemy_options[enemy_key]




module MenuCommonFunctions
  def choose_conjured_defense(attacker)
		ally_list = @data.status_list
		ally_list = ally_list.select { |c| c.role != attacker.role } unless attacker.role == :PC
    conjured_weapons = []
  	ally_list.each do |status|
    	status.items.each do |item|
      	if item.class == ConjuredEquipment and item.block_allies?
          item.set_caster(status)
          conjured_weapons << item
        end
      end
    end
		return :none if conjured_weapons == []
  	weapon_options = ('a'..'z').to_a.zip([:none] + conjured_weapons).to_h.compact
		@option_hash = weapon_options.map { |letter, weapon| [letter, (weapon.class == Symbol ? weapon.to_s : weapon.name)] }.to_h
  	weapon_key = get_menu_selection "(Allies) Choose conjured defense"
		return weapon_options[weapon_key] if weapon_options[weapon_key]
  end

  def choose_defense_action target_char
		action_options = [:flatfooted, :dodge]
    action_options << :primal_tenacity if target_char.special_abilities.any? { |sa| sa.name == 'Primal Tenacity' }
    action_options << :danger_sense if target_char.special_abilities.any? { |sa| sa.name == 'Danger Sense' }
    action_options << :uncanny_dodge if target_char.special_abilities.any? { |sa| sa.name == 'Uncanny Dodge' }

  	weapon_options = ('a'..'z').to_a.zip(action_options + target_char.weapons).to_h.compact
		@option_hash = weapon_options.map { |letter, weapon| [letter, (weapon.class == Symbol ? weapon.to_s : weapon.name)] }.to_h
  	weapon_key = get_menu_selection "(Defender) Choose weapon"
		return weapon_options[weapon_key] if weapon_options[weapon_key]
	end

  def choose_weapon(attacker)
  	weapon_options = ('a'..'z').to_a.zip(attacker.weapons).to_h.compact
		@option_hash = weapon_options.map { |letter, weapon| [letter, weapon.name] }.to_h
  	weapon_key = get_menu_selection "Choose weapon"
		return weapon_options[weapon_key] if weapon_options[weapon_key]
	end

  def choose_enemy(attacker)
		enemy_list = @data.status_list.select { |c| c.role != attacker.role }
  	enemy_options = ('a'..'z').to_a.zip(enemy_list).to_h.compact
		@option_hash = enemy_options.map { |letter, enemy| [letter, enemy.name] }.to_h
		enemy_key = get_menu_selection "Choose target"
		return enemy_options[enemy_key] if enemy_options[enemy_key]
	end
end

module MenuSelectMonsters
	def display_char_by_role
    @display_obj == nil ? @display_obj = Display.new(80) : @display_obj.reset(80)
    
    unless @char_nha
      @char_nha = @data.character_list.map { |char| char.role}.uniq.map { |role| [role, @data.character_list.select { |char| char.role == role }] }.to_h
      @option_hash = {}

      alphabet = ('a'..'z').to_a
      @char_nha.each { |role, char_list| char_list.each { |char| letter = alphabet.shift; @option_hash[letter] = char } }
    end

    lines = @char_nha.map do |group_name, char_list|
      char_display = char_list.map do |char|
        letter = @option_hash.invert[char]
        ["#{'* ' if @selected_char == char}#{letter}. #{char.name}", '']
      end
      [group_name.to_s.capitalize, char_display]
    end
    @display_obj.display_list(lines.to_h)

    @data.status_list.uniq { |status| status.character }.each do |char_status|
      print "(#{@data.status_list.select { |status| status.character == char_status.character }.count}) #{char_status.name}\n"
    end
  end

  def change_monsters
    @selected_char, input = nil
    while (![:exit, 'q'].include? input)
      display_char_by_role
      input = Tools.get_keypress

      if @option_hash[input].class == CharacterSheet
        @selected_char = @option_hash[input]
      elsif input == "+" and @selected_char != nil
        new_char =  CharacterStatus.new(@selected_char)
        if @data.status_list.select { |status| status.character == new_char.character }.count == 0
          new_char.set_mob_index(nil)
        else
          new_char_index = 0
          @data.status_list.each { |status| status.set_mob_index(++new_char_index) }
          new_char.set_mob_index(new_char_index)
        end
        @data.status_list << new_char
      elsif input == "-" and @selected_char != nil
        (index = @data.status_list.find_index { |status| status.character == @selected_char }) && @data.status_list.delete_at(index)
      elsif input == :exit
        break
      end
    end
  end
end

module MenuInitiative
	def display_init
    @display_obj == nil ? @display_obj = Display.new(50) : @display_obj.reset(50)
    @display_obj.display_header('Initiative')
    lines = []
    lines << [ "Init", "Name" ]
    @data.initiative.each do |init|
			mob_count = @data.status_list.select { |status| status.character == init.character }.count
			lines << [init.to_s, "#{init.character.name}#{" x#{mob_count}" if mob_count > 1}"]
		end
    @display_obj.display_section lines
	end

  def roll_initiative
		return unless @data.status_list
    @data.status_list ||= []
    @data.initiative ||= []

    if @data.status_list.map { |status| @data.initiative.any? { |init_roll| init_roll.character == status.character } }.any?
      display_init
      print "\n\n"
    elsif @data.initiative and @data.initiative.count > 0
      print "Initiative doesn't match characters\n\n"
    else
      print "Initiative not found\n\n"
    end

    menu [:manually_input_character_rolls, :roll_for_everyone], false
  end

	def manually_input_character_rolls
    npc_rolls = InitiativeRoll.roll(@data.status_list.select { |status| status.role != :PC })
    npc_rolls.each { |init_roll| print "#{init_roll.character.name} rolled #{init_roll.to_s}\n" }
    pc_rolls = @data.status_list.select { |status| status.role == :PC }.map do |status|
      print "Please input #{status.name}'s roll: "
      input = gets.chomp
      InitiativeRoll.roll_manual(status, input)
    end
    @data.initiative = InitiativeRoll.sort(pc_rolls + npc_rolls)
    @data.save
    display_init
  end

  def roll_for_everyone
    @data.initiative = InitiativeRoll.roll(@data.status_list)
    @data.save
    display_init
  end
end


module MenuCombat
	def combat; display_combat_status; menu([:attack, :cast_spell, :move, :bonus_action, :end_turn, :skip_round], false); end
  def skip_round; handle_afflictions; @data.status_list.each { |status| status.new_initiative }; display_combat_status; end
  def end_turn; @active_char.end_turn; display_combat_status; end
  def move; @active_char.take_action(MOVE_ACTION); end
  def bonus_action; @active_char.take_action(BONUS_ACTION, get_number("How many dice?",(0..20).to_a)); end

	def display_combat_status
    @display_obj == nil ? @display_obj = Display.new(140) : @display_obj.reset(140)
    @display_obj.display_header('Combat')
    @active_char = nil

    lines = []
    lines << [ "Init", "Name", "HP", "Mana", "Combat Dice", "Afflictions", "Damage"]
    @data.initiative.each do |init|
      status_info = [init.to_s]
      @data.status_list.select { |status| status.character == init.character }.each do |status|
        @active_char = status if @active_char == nil and status.turn_complete? == false
        status_info << status.name
        status_info << "#{status.get_remaining_hp}/#{status.max_hp}"
        status_info << "#{status.get_remaining_mana}/#{status.max_mana}"
        status_info << "#{status.combat_pool[:remaining]}/#{status.combat_pool[:maximum]}"
        status_info << "bleed: #{status.health_notes[:bleed]}"
        status_info << "minor: #{status.get_damage(MINOR_DAMAGE)}, major: #{status.get_damage(MAJOR_DAMAGE)}"
        lines << status_info.dup
        status_info = ['']
      end
    end
    if @active_char == nil
      @data.status_list.each do |status|
        status.new_initiative
        @active_char = status if @active_char == nil and status.character == @data.initiative.first.character
      end
    end
    @display_obj.display_section_set_width lines, [10]
    print "\n\n#{@active_char.name}'s turn\n\n"; 
  end

  #def choose_conjured_defense
		#ally_list = @data.status_list
		#ally_list = ally_list.select { |c| c.role != char.role } unless @active_char.role == :PC
    #conjured_weapons = []
  	#ally_list.each do |status|
    	#status.items.each do |item|
      	#if item.class == ConjuredEquipment and item.block_allies?
          #item.set_caster(status)
          #conjured_weapons << item
        #end
      #end
    #end
		#return :none if conjured_weapons == []
  	#weapon_options = ('a'..'z').to_a.zip([:none] + conjured_weapons).to_h.compact
		#@option_hash = weapon_options.map { |letter, weapon| [letter, (weapon.class == Symbol ? weapon.to_s : weapon.name)] }.to_h
  	#weapon_key = get_menu_selection "(Allies) Choose conjured defense"
		#return weapon_options[weapon_key] if weapon_options[weapon_key]
  #end

  #def choose_def_weapon target_char
		#action_options = [:flatfooted, :dodge]
    #action_options << :primal_tenacity if target_char.special_abilities.any? { |sa| sa.name == 'Primal Tenacity' }
    #action_options << :danger_sense if target_char.special_abilities.any? { |sa| sa.name == 'Danger Sense' }
    #action_options << :uncanny_dodge if target_char.special_abilities.any? { |sa| sa.name == 'Uncanny Dodge' }

  	#weapon_options = ('a'..'z').to_a.zip(action_options + target_char.weapons).to_h.compact
		#@option_hash = weapon_options.map { |letter, weapon| [letter, (weapon.class == Symbol ? weapon.to_s : weapon.name)] }.to_h
  	#weapon_key = get_menu_selection "(Defender) Choose weapon"
		#return weapon_options[weapon_key] if weapon_options[weapon_key]
	#end

  #def choose_weapon
  	#weapon_options = ('a'..'z').to_a.zip(@active_char.weapons).to_h.compact
		#@option_hash = weapon_options.map { |letter, weapon| [letter, weapon.name] }.to_h
  	#weapon_key = get_menu_selection "Choose weapon"
		#return weapon_options[weapon_key] if weapon_options[weapon_key]
	#end

  #def choose_enemy char
		#enemy_list = @data.status_list.select { |c| c.role != char.role }
  	#enemy_options = ('a'..'z').to_a.zip(enemy_list).to_h.compact
		#@option_hash = enemy_options.map { |letter, enemy| [letter, enemy.name] }.to_h
		#enemy_key = get_menu_selection "Choose target"
		#return enemy_options[enemy_key] if enemy_options[enemy_key]
	#end

  def attack
  	weapon = choose_weapon
    attack_bonus = @active_char.attack_bonus(weapon)
    attack_bonus_string = "#{'+' if attack_bonus >= 0}#{attack_bonus}"

    attack_dice = get_number("Attack Bonus #{attack_bonus_string}, How many attack dice (2-#{@active_char.attack_dice})", (0..@active_char.attack_dice).to_a)
    target_char = choose_enemy @active_char
    dodge_successes, def_bonus = defend(target_char, attack_bonus)

		tn = @active_char.attack_tn(weapon, (-1 * def_bonus))

    base_damage = weapon.get_base_weapon_damage(@active_char) + attack_bonus - target_char.get_dr(@active_char)
    success_mod = @active_char.attack_result_mod(weapon, (-1 * def_bonus))
    base_damage_string = "#{'+' if base_damage + success_mod >= 0}#{base_damage + success_mod}"
    attack_success = get_number("(Attacker)How many successes (TN #{tn}), (dmg success#{base_damage_string})", (-10..(2*attack_dice)).to_a) 
    attack_success += success_mod
    @active_char.spend_dice(attack_dice + weapon.speed)

    if attack_success - dodge_successes < 2
      print " ** Attack Missed ** #{attack_success - dodge_successes} < 2 (#{attack_success} - #{dodge_successes})\n"
    else
      damage = attack_success + base_damage

      if damage < 0
        print " ** Attack hit, but no damage ** #{damage} (#{attack_success} + #{base_damage})\n"
      elsif damage == 0
        bleed = weapon.get_bleed_mod + damage
        print " ** Attack hit and causes #{bleed} bleed ** (#{attack_success} + #{base_damage})\n"
      else
        damage = damage - get_number("Increase damage reduction (0)?", (0..20).to_a)
        damage = get_number("Fudge Damage? (damage #{damage}, threshold #{weapon.get_threshold + target_char.get_resiliance})", (0..100).to_a, damage) 
        resiliance = get_number("Increase Resiliance (0)? (#{target_char.get_resiliance})", (0..100).to_a, 0) + target_char.get_resiliance

        minor_damage = [damage, resiliance].min
        moderate_damage = [[damage - minor_damage, 0].max, weapon.get_threshold].min
        major_damage = [damage - minor_damage - moderate_damage, 0].max

        target_char.add_damage(Damage.new(:physical, MINOR_DAMAGE, minor_damage)) if minor_damage > 0
        target_char.add_damage(Damage.new(:physical, MODERATE_DAMAGE, moderate_damage)) if moderate_damage > 0
        target_char.add_damage(Damage.new(:physical, MAJOR_DAMAGE, major_damage)) if major_damage > 0

        bleed = weapon.get_bleed_mod + damage
        target_char.update_bleed(bleed)

        print " ** #{@active_char.name} hits #{target_char.name} for #{damage} points of damage **\n"
        print "  #{target_char.name} reduces #{minor_damage} points to minor damage, and takes #{major_damage} points of major damage\n"
        print "  #{target_char.name} takes #{bleed} bleed (Total: #{target_char.bleed}\n" if bleed > 0
      end

      bonus_damage = get_number("How much bonus damage (0)", (0..20).to_a, 0)
      target_char.add_damage(Damage.new(:bonus, MODERATE_DAMAGE, bonus_damage)) if bonus_damage > 0
    end
    Tools.press_any_key
    display_combat_status
  end

  def defend(target_char, attack_bonus)
    conjured_defense = choose_conjured_defense

    if conjured_defense.class == ConjuredEquipment
      conjured_char = conjured_defense.caster
      conjured_base_bonus = conjured_char.attack_bonus(conjured_defense)
      conjured_bonus = conjured_base_bonus - attack_bonus
      max_def_dice = conjured_char.magic_dice(conjured_defense.skill)
      def_bonus_string = "#{'+' if conjured_bonus >= 0}#{conjured_bonus}"
      def_request_string = "Conjured Defense Bonus #{def_bonus_string} (#{conjured_base_bonus}-#{attack_bonus}), How many defense dice (2-#{max_def_dice})"
      conjured_dice = get_number(def_request_string, (2..max_def_dice).to_a)

      tn = conjured_char.attack_tn(conjured_defense, (-1 * attack_bonus))
      conjured_successes = [0, get_number("(Allies)How many successes (TN #{tn})", (-10..(2*conjured_dice)).to_a) ].max
      conjured_char.spend_dice(conjured_dice)
    else
      conjured_bonus, conjured_successes = 0
    end

  	weapon = choose_def_weapon target_char
    def_base_bonus = {dodge: target_char.attr_bonus(:dex),flatfooted: -2, unaware: -4, uncanny_dodge: 0}[weapon].to_i
    return [0, def_base_bonus] if [:flatfooted, :unaware, :uncanny_dodge].include? weapon

    def_base_bonus = target_char.attack_bonus(weapon) unless weapon.class == Symbol
    def_bonus = def_base_bonus
    def_bonus = def_bonus - attack_bonus unless weapon == :dodge
    def_bonus_string = "#{'+' if def_bonus >= 0}#{def_bonus}"
    max_def_dice = (weapon == :dodge) ? target_char.attr_dice(:dex) : target_char.attack_dice

		def_request_string = "Defense Bonus #{def_bonus_string} (#{def_base_bonus}-#{attack_bonus}), How many defense dice (2-#{max_def_dice})"
    def_dice = get_number(def_request_string, (0..max_def_dice).to_a)
    def_weapon_speed = (weapon.class == Symbol) ? 0 : weapon.speed
    target_char.spend_dice(def_dice + def_weapon_speed)

    if weapon.class != Symbol
      tn = target_char.attack_tn(weapon, (-1 * attack_bonus))
      def_result_mod = target_char.attack_result_mod(weapon, (-1 * attack_bonus))
    else #I am assuming this is dodge
      tn = target_char.attr_tn(:dex)
      def_result_mod = target_char.attr_result_mod(:dex)
    end
    #dodge_result_mod_string = "#{'+' if dodge_result_mod >= 0}#{dodge_result_mod}"
    #dodge_successes = get_number("(Defender)How many successes (TN #{tn}) (#{dodge_result_mod_string})", (-10..(2*dodge_dice)).to_a) 
    def_successes = get_number("(Defender)How many successes (TN #{tn})", (-10..(2*def_dice)).to_a) 

    def_base_bonus = [def_base_bonus, conjured_base_bonus].max if conjured_defense.class == ConjuredEquipment
    return (def_successes + def_result_mod + conjured_successes), def_base_bonus
  end

  def cast_spell; end
  def handle_afflictions; end
end
