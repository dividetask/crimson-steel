require 'irb'
require_relative 'declarations.rb'
require_relative 'datastore.rb'
require_relative 'roll.rb'
require_relative 'items.rb'
#require_relative 'combat.rb'
require_relative 'character.rb'
require_relative 'display.rb'
#require_relative 'general.rb'
#require_relative 'rules.rb'
#require_relative 'tests.rb'
require_relative 'reset.rb'

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

module Tools
	def self.map2d(a2d, e_code, r_code); a2d.map.with_index { |row, r| r_code.call(row.map.with_index { |e, c| e_code.call(e, r, c) }, r) }; end
	def self.each2d(a2d, e_code, r_code); a2d.each.with_index { |row, r| r_code.call(row.each.with_index { |e, c| e_code.call(e, r, c) }, r) }; end
	def self.pad_array(a2d); return a2d.map { |row| row + Array.new(a2d.map(&:length).max - row.length, '') }; end
	def self.rotate(a2d); return pad_array(a2d).transpose; end
	def self.rotatemap2d(a2d, e_code, r_code); map2d(rotate(a2d), e_code, r_code); end
end

def display_character_sheet(char, opt)
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

	#skill_display = char.skills.map do |skill, skill_p| 
	skill_display = char.skills.select { |skill, skill_p| ![:melee, :ranged].include?(skill) }.map do |skill, skill_p| 
		[opt.add(skill.to_s, skill) , char.ranks(skill).to_s, "#{char.dice(skill)}d (TN #{char.base_tn(skill)})", "-"] 
	end

	#attr_display = SKILL_NAME_SYMS.map do |name, attr| 
		#attr_skill = "#{char.attr_dice(attr)}d (TN #{char.attr_tn(attr)})"
		#attr_skill += "#{char.attr_bonus(attr)}" if char.attr_bonus(attr) != 0
		#attr_save = "#{char.save_dice(attr)}d (TN #{char.save_tn(attr)})"
		#attr_save += "#{char.save_bonus(attr)}" if char.save_bonus(attr) != 0
		#[name, char[attr].to_s, attr_skill, attr_save]
	#end

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

def cycle_through_characters(data)
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

			Display.display_check(msg, roll) if roll
			#Display.draw_dice(roll) if roll
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


#		equipment = []
  																	#class, 			level, 	str, 	dex, 	con, 	int, 	wis, 	cha
#		stats = CharacterStats.new(:NPC, :barbarian, 	3, 			14, 	11, 	14, 	8, 	8, 	9, {melee: 3, ranged: 2}) 
#		equipment << Equipment.new("Leather", :armor, :light, 0)
#		equipment << Equipment.new("Maul", :weapon, :maul, 0)
#		equipment << Equipment.new("Javelin", :weapon, :javelin, 0)
#		equipment << Equipment.new("Punch", :weapon, :punch, 0)
#		char = Character.new("NPC Fighter 3", Gender.m, stats, equipment)

#p char.perception()
#exit


#ResetCharacters.overwrite_data
#data = DataStore.new('campaign')
#char = data.character_list.first

#p char.perception()

	#menu.display_section( [ ["Human #{char.klass.to_s.capitalize}", "Level #{char.level}", "Magical Density 1"],
                          #["Combat Pool: ?", "Perception: #{Skill.perception(char)}", "Initiative: #{Skill.initiative(char)}"],
                          #["Damage Reduction: ?", "Damage Resilience: ?", "Speed: ?"],
#exit

ResetCharacters.overwrite_data

data = DataStore.new('campaign')
cycle_through_characters(data)

#character_creation_menu(data)


																#class, 			level, 	str, 	dex, 	con, 	int, 	wis, 	cha
#stats = CharacterStats.new(:PC, :barbarian, 	3, 			16, 	14, 	16, 	10, 	12, 	9, {melee: 3, ranged: 2}) 
#olga = Character.new("Olga", Gender.f, stats, [])

#data = DataStore.new('campaign')
#data.character_list = [olga]
#data.save


#run_tests = RunTests.new
#run_tests.single_step_spider_ambush
#run_tests.test_spider_ambush
#run_tests = PlayTest.new
#run_tests.fight_spiders 5

exit
#cultist = Character.get_cult_leaders_sheet
#lysander = Character.get_lysanders_sheet
#olga = Character.get_olgas_sheet
#basic_combat = BasicCombat.new(lysander, cultist, true)
#basic_combat.simulate_combat
