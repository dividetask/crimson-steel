
#class SimpleAction
  #attr_reader :char_obj, :char_sym, :weapon
	#def initialize(char_obj, char_sym, weapon); @char_obj, @char_sym, @weapon = char_obj.dup, char_sym, weapon.dup; end
	#def get_multiple(count); return Array.new(count) { @char_obj.dup }; end
#end

#class SheetManager
  #attr_reader :player_characters, :sheets, :status_list, :selected_sym, :selected_index

  #def add_characters enemy_list
		#@sheets = {}
		#@sheets[:lysander] = Character.get_lysanders_sheet
		#@sheets[:olga] = Character.get_olgas_sheet
		#@sheets[:stumpy] = Character.get_stumpys_sheet
		#@player_characters = @sheets.keys
		#@status_list = @sheets.to_a.map { |char| [char[0], CharacterStatus.new(char[1])] }.to_h

		#enemy_list.each do |enemy_sym, enemy_details|
			#@sheets[enemy_sym] = enemy_details[:sheet]
			#@status_list[enemy_sym] = Array.new(enemy_details[:count]) { CharacterStatus.new(enemy_details[:sheet]) }
		#end
	#end

	#def get_selected_status
		#if @selected_index
			#@status_list[@selected_sym][@selected_index]
		#else
			#@status_list[@selected_sym]
		#end
	#end

	#def get_selected_name
		#if @selected_index
			#"#{@status_list[@selected_sym][@selected_index].character.name} ##{@selected_index + 1}"
		#else
			#"#{@status_list[@selected_sym].character.name}"
		#end
	#end

	#def get_rand_pc
		#@selected_sym = @player_characters.sample
		#@selected_index = nil
	#end

	#def get_first_enemy
		#enemies = @sheets.select { |k, v| !(@player_characters.include? k) }
		#@selected_sym = enemies.first.first
		#@selected_index = 0 #Need to add code for skipping downed enemies
	#end

#end
#class StatusManager

class PlayTest
  attr_reader :sheet_mng, :action_list, :turn_order, :init_roll
	def initialize; @sheet_mng = StatusManager.new; end

	def print_turn_order
		print "Turn Order\n----------\n"
		@turn_order.each.with_index { |char_sym, i| print "#{i+1}: #{char_sym.to_s} (rolled #{@init_roll[char_sym].to_s})\n" }
		print "\n"
	end

	def fight_spiders count
		monster_sym, monster_obj = [:spiders, Character.get_medium_spider]
		monster_attack = monster_obj.equipment.find { |x| x.category == :weapon and x.subcategory == :bite }
		monster_max_attack = RulesMath.get_max_attack_dice(monster_obj, monster_attack)
		@sheet_mng.add_characters({monster_sym => {sheet: monster_obj, count: count}})

		@init_roll = InitiativeRoll.roll(@sheet_mng.sheets)
		@turn_order = InitiativeRoll.turn_order(@init_roll)

		print_turn_order

		@turn_order.each do |char_sym|
			print "#{char_sym.to_s}'s turn\n----------\n"
			if char_sym == monster_sym
				@sheet_mng.status_list[monster_sym].each.with_index do |enemy, index|
					@sheet_mng.get_rand_pc
					print "#{char_sym.to_s} ##{index+1} attacks #{@sheet_mng.get_selected_name}\n\n"

#p enemy.character.class, @sheet_mng.get_selected_status.character.class
#exit
					combat_math = CombatMath.new(enemy.character, @sheet_mng.get_selected_status.character)
					attack_details = combat_math.roll_attack(monster_attack, monster_max_attack, 0)
					attack_details = combat_math.roll_damage(monster_attack, attack_details) 
					attack_details.add_notes(:attack_verb, 'bites')
					Display.display_attack_message attack_details
					print "\n"
    			Display.draw_dice(attack_details.rolls)
					print "\n"
					#Display.press_any_key
				end
			elsif char_sym == :lysander
				@sheet_mng.get_first_enemy
				print "#{char_sym.to_s.capitalize} attacks #{@sheet_mng.get_selected_name}\n\n"

				combat_math = CombatMath.new(@sheet_mng.sheets[char_sym], @sheet_mng.get_selected_status.character)
				player_attack = @sheet_mng.sheets[char_sym].equipment.find { |x| x.category == :weapon and x.subcategory == :longbow }
				attack_details = combat_math.roll_attack(player_attack, 8, 0)
				attack_details = combat_math.roll_damage(player_attack, attack_details)
				attack_details.add_notes(:attack_verb, 'shoots')
				Display.display_attack_message attack_details
				print "\n"
    		Display.draw_dice(attack_details.rolls)
				print "\n"
				Display.press_any_key
			elsif char_sym == :stumpy
				@sheet_mng.get_first_enemy
				print "#{char_sym.to_s.capitalize} attacks #{@sheet_mng.get_selected_name}\n\n"

				combat_math = CombatMath.new(@sheet_mng.sheets[char_sym], @sheet_mng.get_selected_status.character)
				player_attack = @sheet_mng.sheets[char_sym].equipment.find { |x| x.category == :weapon and x.subcategory == :battleaxe }
				attack_details = combat_math.roll_attack(player_attack, 8, 0)
				attack_details = combat_math.roll_damage(player_attack, attack_details)
				attack_details.add_notes(:attack_verb, 'slashes')
				Display.display_attack_message attack_details
				print "\n"
    		Display.draw_dice(attack_details.rolls)
				print "\n"
				Display.press_any_key
			elsif char_sym == :olga
				@sheet_mng.get_first_enemy
				print "#{char_sym.to_s.capitalize} attacks #{@sheet_mng.get_selected_name}\n\n"

				combat_math = CombatMath.new(@sheet_mng.sheets[char_sym], @sheet_mng.get_selected_status.character)
				player_attack = @sheet_mng.sheets[char_sym].equipment.find { |x| x.category == :weapon and x.subcategory == :greataxe }
				attack_details = combat_math.roll_attack(player_attack, 8, 0)
				attack_details = combat_math.roll_damage(player_attack, attack_details)
				attack_details.add_notes(:attack_verb, 'slashes')
				Display.display_attack_message attack_details
				print "\n"
    		Display.draw_dice(attack_details.rolls)
				print "\n"
				Display.press_any_key
			end
		end
	end
end

class RunTests
  attr_reader :player_characters

  def get_characters
		@player_characters = {}
		@player_characters[:lysander] = Character.get_lysanders_sheet
		@player_characters[:olga] = Character.get_olgas_sheet
		@player_characters[:stumpy] = Character.get_stumpys_sheet
	end

	def run_spider_ambush iterations
		get_characters
		spider = Character.get_medium_spider
		spider_bite = spider.equipment.find { |x| x.category == :weapon and x.subcategory == :bite }
		number_of_attack_dice = RulesMath.get_max_attack_dice(spider, spider_bite)
		result_log = @player_characters.transform_values { [] } 

		attack_log = []
		iterations.times do
			@player_characters.each do |character_name, character|
				combat_math = CombatMath.new(spider, character, false)
				attack_details = combat_math.roll_attack(spider_bite, number_of_attack_dice, 0)
				attack_details = combat_math.roll_damage(spider_bite, attack_details) 
				attack_details.add_notes(:attack_verb, 'bites')
				attack_log << attack_details
				result_log[character_name] << attack_details.notes[:major_damage].to_i
			end
		end
		return {attack_log: attack_log, major_damage: result_log}
	end

	def single_step_spider_ambush
		results = run_spider_ambush 1
		results[:attack_log].each do |attack_details|
			Display.display_attack_message attack_details
			print "\n"
    	Display.draw_dice(attack_details.rolls)
			print "\n"
			Display.press_any_key
		end
	end

	def test_spider_ambush
		results = run_spider_ambush 100
		
		results[:major_damage].each do |character_name, damage_array|
			mean = damage_array.sum / damage_array.size.to_f
			median = damage_array.sort[damage_array.size / 2]
			mode = damage_array.tally.max_by { |k, v| v }.first
			no_damage = 100 * damage_array.count { |x| x == 0 || x.nil? } / damage_array.size.to_f

			print "#{character_name} avoided major damage #{no_damage}%\n"
			print "\t\taverage #{mean}, median #{median}, mode #{mode}\n\n\n"
		end
	end
end
