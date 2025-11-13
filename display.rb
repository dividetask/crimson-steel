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
end

class Menu
  include MenuSelectMonsters
  include MenuInitiative
  include MenuCombat
  attr_reader :display_obj, :data, :option_hash

	def initialize(data); @display_obj, @option_hash = nil; @data = data; end
  def main_menu; menu [:change_monsters, :roll_initiative, :combat]; end
  ##def main_menu; menu [:change_monsters, :view_characters, :roll_initiative, :view_combat]; end

  def get_number(message, accepted_number_list)
    input = nil
    while (true)
      print "#{message} "
      input = gets.chomp
      break if input == 'q'
      input = input.to_i
      break if accepted_number_list.include? input
    end
    input
  end

  def get_menu_selection message
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
    lines << [ "Init", "Name", "HP", "Afflictions", "Combat Dice"]
    @data.initiative.each do |init|
      status_info = [init.to_s]
      @data.status_list.select { |status| status.character == init.character }.each do |status|
        @active_char = status if @active_char == nil and status.turn_complete? == false
        status_info << status.name
        status_info << "#{status.get_remaining_hp}/#{status.max_hp}"
        status_info << "bleed: #{status.health_notes[:bleed]}"
        status_info << "#{status.combat_pool[:remaining]}/#{status.combat_pool[:maximum]}"
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

  def choose_weapon
  	weapon_options = ('a'..'z').to_a.zip(@active_char.weapons).to_h.compact
		@option_hash = weapon_options.map { |letter, weapon| [letter, weapon.name] }.to_h
  	weapon_key = get_menu_selection "Choose weapon"
		return weapon_options[weapon_key] if weapon_options[weapon_key]
	end

  def choose_enemy
  	enemy_options = ('a'..'z').to_a.zip(@data.status_list).to_h.compact
		@option_hash = enemy_options.map { |letter, enemy| [letter, enemy.name] }.to_h
		enemy_key = get_menu_selection "Choose target"
		return enemy_options[enemy_key] if enemy_options[enemy_key]
	end

  def attack
  	weapon = choose_weapon
    attack_dice = get_number("How many attack dice for #{@active_char.name} (2-#{@active_char.attack_dice})", (0..@active_char.attack_dice).to_a)
    target_char = choose_enemy
    dodge_successes, def_tn_mod = defend(target_char, @active_char.attack_tn_mod(weapon))
    attack_success = get_number("How many attack successes #{@active_char.name}", (-10..(2*@active_char.attack_dice)).to_a) 
    if attack_success - dodge_successes < 2
      @active_char.spend_dice(attack_dice + weapon.speed)
      print " ** Attack Missed ** #{attack_success - dodge_successes} < 2 (#{attack_success} - #{dodge_successes})\n"
    else
      @active_char.spend_dice(attack_dice + weapon.speed)

			base_damage = weapon.get_base_weapon_damage(@active_char)
      damage = attack_success + base_damage
      defender_dr = target_char.get_dr(@active_char)
      damage -= defender_dr

      if damage < 0
        print " ** Attack hit, but no damage ** #{damage} (#{attack_success} + #{base_damage} - #{defender_dr})\n"
      elsif damage == 0
        bleed = weapon.get_bleed_mod
        print " ** Attack hit and causes #{bleed} bleed ** (#{attack_success} + #{base_damage} - #{defender_dr})\n"
      else
        minor_damage = [damage, target_char.get_resiliance].min
        moderate_damage = [[damage - minor_damage, 0].max, weapon.get_threshold].min
        major_damage = [damage - minor_damage - moderate_damage, 0].max

        target_char.add_damage(Damage.new(:physical, MINOR_DAMAGE, minor_damage)) if minor_damage > 0
        target_char.add_damage(Damage.new(:physical, MODERATE_DAMAGE, moderate_damage)) if moderate_damage > 0
        target_char.add_damage(Damage.new(:physical, MAJOR_DAMAGE, major_damage)) if major_damage > 0

        bleed = weapon.get_bleed_mod + damage
        target_char.update_bleed(bleed)

        print " ** #{@active_char.name} hits #{target_char.name} for #{damage} points of damage **\n"
        print "  #{target_char} reduces #{minor_damage} points to minor damage, and takes #{major_damage} points of major damage\n"
        print "  #{target_char} takes #{bleed} bleed (Total: #{target_char.bleed}\n" if bleed > 0
      end

      bonus_damage = get_number("How much bonus damage", (0..20).to_a)
      target_char.add_damage(Damage.new(:bonus, MODERATE_DAMAGE, bonus_damage)) if bonus_damage > 0
    end
    Tools.press_any_key
    display_combat_status
  end

  def defend(target_char, attack_tn_mod)
    dodge_dice = get_number("How many dodge dice for #{target_char.name}", (0..target_char.attr_dice(:dex)).to_a)
    target_char.spend_dice(dodge_dice)
    dodge_successes = get_number("How many defense successes", (-10..10).to_a)
    def_tn_mod = 0
    return dodge_successes, def_tn_mod
  end

  def cast_spell; end
  def handle_afflictions; end
end





