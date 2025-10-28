require 'securerandom'
require 'io/console'

$deck = (1..10).to_a

def get_text_color_code(color)
	if color == :blue
  	return "\e[34m"
	elsif color == :black
  	return "\e[30m"
	elsif color == :red
  	return "\e[31m"
	elsif color == :green
  	return "\e[32m"
	elsif color == :yellow
  	return "\e[33m"
	elsif color == :orange
  	return "\e[38;5;208m"
	end
end

def get_background_color_code(color)
	if color == :white
  	return "\e[47m"
	elsif color == :lgrey
  	return "\e[47;2m"
	elsif color == :dgrey
  	return "\e[48;5;240m"
	elsif color == :reset or color == :black
		return "\e[0m"
	end
end

def print_die(value, color)
	output_text = ""
	output_text << get_background_color_code(:reset)
	output_text << " "
	output_text << get_background_color_code(:white)
	output_text << get_text_color_code(color)
	output_text << " #{value} "
	output_text << get_background_color_code(:reset)
	output_text << " "
  print "#{output_text}"
end

def print_colored_line(line_details, line_color = :black)
	output_text = ""
	line_details.each do |text_details|
		output_text << get_text_color_code(text_details[:color])
		output_text << text_details[:text]
	end

	print get_text_color_code(:reset)
  width = IO.console.winsize[1]
 	padded = output_text.ljust(width)  # Pad with spaces to fill the line
	print "#{get_background_color_code(line_color)}#{padded}\n"
	print get_text_color_code(:reset)
end

def press_any_key
	puts "Press Enter to continue..."
	gets
end

# COMMON PARAMETERS
		# attack_results = {success?: = <BOOL>, success_count: <INT>, total_damage: <INT>, bleed_increase: <INT>, attack_notes: <HASH>, damage_notes: <HASH>}
				# attack_notes 							= {success_count: <INT>, attack_roll: <HASH>, dodge_roll: <HASH>}
					# attack_roll/dodge_roll		= {dice_results: <INT>, dice_rolls: <ARRAY>}
				# damage_notes 							= {damage_adjustment: <INT>, base_damage: <INT>, damage_reduction: <INT>, typed_damage: <INT>, typed_damage_list: <HASH>}

	# attacker_details, and defender_details  follow char_details
	# char_details = {name: <STRING>, pronoun: ("him", "her"), hp: <INT>, combat_pool: <INT>, <HASH> (:density, :armor, :shield, :weapon, :combat_skill, action_details)}
		# :density {rank: <INT>, damage_reduction: <INT>}
		# :armor {bonus: <INT>, damage_reduction: <INT>}
		# :shield {bonus: <INT>, damage_reduction: <INT>}
		# :weapon {name: <STRING>, bonus: <INT>, damage_bonus: <INT>, typed_damage: <HASH>}
			# :typed_damage {emotional: <INT>, radiant: <INT>, fire: <INT>}
		# :combat_skill {ranks: <INT>, static_bonus: <INT>, bonus_dice: <INT>, attribute_dice: <INT>}
		# :action_details {dodge_dice: <INT>, attack_action_list: <ARRAY>}
			# :attack_action_details {attack_type: (:melee, :ranged, :magic_ranged, :magic_melee, :nothing), attack_dice: <INT>, weapon: <HASH>}
			# :weapon {name: <STRING>, bonus: <INT>, damage_bonus: <INT>, typed_damage: <HASH>}
				# :typed_damage {emotional: <INT>, radiant: <INT>, fire: <INT>}

def roll_dice(number_of_dice)
	# number_of_dice 					is expected to be nil or an integer
	# returns an array of integers whose value is between 1 and 10

	return [] if (number_of_dice == nil or number_of_dice <= 0)
	dice_rolls = Array.new(number_of_dice) { $deck.shuffle!(random: SecureRandom)[0] }

	return dice_rolls
end

def get_dice_results(number_of_dice, die_values)
	# number_of_dice 					is expected to be nil or an integer
	# dice_values 					 	is expected to be nil or a hash with zero or more of the following keys: fumble, crit, target, success, default
	# returns a hash with the zero or more of following keys: dice_results, dice_rolls

	die_values = {} unless die_values
	die_values = {fumble: -1, crit: 2, target: 9, success: 1, default: 0}.merge(die_values)
	dice_rolls = roll_dice(number_of_dice)
	dice_results = dice_rolls.sum { |r| r == 1 ? die_values[:fumble] : r == 10 ? die_values[:crit] : r >= die_values[:target] ? die_values[:success] : die_values[:default] }

	return {dice_results: dice_results.clone, dice_rolls: dice_rolls.clone}
end

				# tn_notes = {attack_tn: <INT>, damage_tn: <INT>, dodge_tn: <INT>, starting_successes: <INT>, starting_failures: <INT>, use_weapon?: <BOOL>}
def adjust_tn(attacker_details, defender_details, attack_type, use_weapon? = false)
	# attack_type: (:melee, :ranged, :magic_ranged, :magic_melee, :nothing)
	# use_weapon? <BOOLEAN>

	tn_notes = {attack_tn: nil, damage_tn: 7, dodge_tn: nil, starting_successes: nil, starting_failures: nil, use_weapon?: use_weapon?}
	tn_notes[:attack_tn], tn_notes[:dodge_tn] = [:melee, :magic_melee].include?(attack_type) ? [7,7] : [9,9]

	attacker_total_bonus = attacker_details[:combat_skill][:static_bonus] + attacker_details[:weapon][:bonus]
	defender_total_bonus = defender_details[:armor][:bonus]
	defender_total_bonus += defender_details[:combat_skill][:static_bonus] if defender_details[:shield] or use_weapon?

	if defender_details[:shield]
		if use_weapon? and defender_details[:weapon][:bonus] > defender_details[:shield][:bonus]
			defender_total_bonus += defender_details[:weapon][:bonus]
		else
			defender_total_bonus += defender_details[:shield][:bonus]
		end
	end

	tn_notes[:attack_tn] += defender_total_bonus - attacker_total_bonus
	tn_notes[:dodge_tn] += attacker_total_bonus - defender_total_bonus

	tn_notes[:starting_failures] = [0, tn_notes[:attack_tn] - 9].max
	tn_notes[:starting_successes] = [0, 4 - tn_notes[:attack_tn]].max
	tn_notes[:attack_tn] = [4, [9, tn_notes[:attack_tn]].min].max
	tn_notes[:dodge_tn] = [4, [9, tn_notes[:dodge_tn]].min].max

	return tn_notes.dup
end

				# attack_notes 							= {success_count: <INT>, attack_roll: <HASH>, dodge_roll: <HASH>}
				# attack_roll/dodge_roll		= {dice_results: <INT>, dice_rolls: <ARRAY>}
def roll_attack(attacker_details, defender_details, tn_notes, attack_action_details)
	# defender_details is expected to be a Hash
	# defender_details[:action_details] is expected to be a Hash
	# defender_details[:action_details][:dodge_dice] is expected to be an Integer
	# tn_notes is expected to be a Hash with the following keys: :attack_tn, :damage_tn, :dodge_tn, :starting_successes, :starting_failures, :use_weapon?
	# attack_action_details is expected to be a Hash
		# attack_action_details[:attack_type] is expected to be :melee, :ranged, :magic_ranged, or :magic_melee
		# attack_action_details[:attack_dice] is expected to be a Positive Integer
		# attack_action_details[:weapon] is expected to be a Hash
		# attack_action_details[:weapon] {name: <STRING>, bonus: <INT>, damage_bonus: <INT>, typed_damage: <HASH>}
			# attack_action_details[:weapon][:typed_damage] {emotional: <INT>, radiant: <INT>, fire: <INT>}

	# returns a hash with the following keys: :success_count, :attack_roll, :dodge_roll

	attack_notes = {success_count: nil, attack_roll: nil, dodge_roll: nil}
	attack_notes[:attack_roll] = get_dice_results(attack_action_details[:attack_dice], {target: tn_notes[:attack_tn]})
	attack_notes[:dodge_roll] = get_dice_results(defender_details[:action_details][:dodge_dice], {target: tn_notes[:dodge_tn]})

	attack_notes[:success_count] = attack_notes[:attack_roll][:dice_results] + tn_notes[:starting_successes]
	attack_notes[:success_count] -= (attack_notes[:dodge_roll][:dice_results] + tn_notes[:starting_failures])

	return attack_notes.dup
end

				# damage_notes 							= {damage_adjustment: <INT>, base_damage: <INT>, damage_reduction: <INT>, typed_damage: <INT>, typed_damage_list: <HASH>}
def roll_damage(attacker_details, defender_details, tn_notes)
	damage_notes = {damage_adjustment: nil, base_damage: nil, damage_reduction: nil, typed_damage: nil, typed_damage_list: {}}

	magic_density_dr = [0, defender_details[:density][:damage_reduction] - attacker_details[:density][:damage_reduction]].max
	equimpent_dr = defender_details[:armor][:bonus] + defender_details[:armor][:damage_reduction]
	equimpent_dr += defender_details[:shield][:bonus] + defender_details[:shield][:damage_reduction] if defender_details[:shield]
	damage_notes[:damage_reduction] = magic_density_dr + equimpent_dr
	
	damage_notes[:base_damage] = attacker_details[:weapon][:base_damage_bonus] + attacker_details[:weapon][:bonus]
	damage_notes[:typed_damage] = 0

	attacker_details[:weapon][:typed_damage].each do |damage_type, damage_dice|
		dice_values = {target: tn_notes[:attack_tn], crit: 2, fumble: 0}
		dice_values = {target: tn_notes[:attack_tn], crit: 3, fumble: 0} if damage_type == :emotional
		damage_notes[:typed_damage_list][damage_type] = get_dice_results(damage_dice, dice_values, damage_type.to_s)
		damage_notes[:typed_damage] += damage_notes[:typed_damage_list][damage_type][:dice_results]
	end

	damage_notes[:damage_adjustment] = damage_notes[:base_damage] - damage_notes[:damage_reduction]

	return damage_notes
end


###############

#def roll_attack(attacker_details, defender_details, tn_notes, attack_action_details)

#def adjust_tn(attacker_details, defender_details, attack_type, use_weapon? = false)
#	# attack_type: (:melee, :ranged, :magic_ranged, :magic_melee, :nothing)
##	# use_weapon? <BOOLEAN>

def simulate_an_attack(attacker_details, defender_details, attack_dice)

	#tn_notes = adjust_tn(attacker_details, defender_details, attack_type)

	attack_roll = roll_attack(attacker_details, defender_details, tn_notes, attack_dice)

	return_results = {message: "", damage: 0, success: false}

	return return_results.merge({message: "Missed", attack_roll: attack_roll}) if attack_roll < 2

	return_results[:damage_breakdown] = roll_damage(attacker_details, defender_details)
	return_results[:damage_breakdown][:physical_damage] = attack_roll + return_results[:damage_breakdown][:damage_adjustment]
	total_damage = return_results[:damage_breakdown][:physical_damage] + return_results[:damage_breakdown][:typed_damage]
	return_results[:damage_breakdown][:total_damage] = total_damage

	return return_results.merge({message: "No damage", attack_roll: attack_roll}) if total_damage < 0

	return_results[:bleed] = return_results[:damage_breakdown][:physical_damage] >= 0 ? return_results[:damage_breakdown][:physical_damage] + 5 : 0
	return return_results.merge({message: "Hit", damage: total_damage, attack_roll: attack_roll, success: true})
end

def handle_bleed(bleed, modifiers)
	return {bleed_damage: 0, base_damage: 0} if bleed <= 0

	details = {base_damage: (1 + (bleed / 10).floor) }
	details[:bleed_check] = roll_dice(modifiers[:defender_con], "Bleeding Save")
	details[:bleed_calculation] = details[:bleed_check].sum { |r| r == 1 ? -1 : r == 10 ? 2 : r == 9 ? 1 : 0 }
	details[:bleed_damage] = [0, [details[:base_damage] + 1, details[:base_damage] - details[:bleed_calculation]].min].max

	debug_log("Bleed Check", details)

	return details
end

def display_round_information(round, current_hp, max_hp)
	line_details = []
	line_details << {color: :black, text: " " * 60} 
	line_details << {color: :blue, text: "Round #{round}"}
	line_details << {color: :black, text: " (#{current_hp}/#{max_hp})"}

	print_colored_line(line_details, :white)
end

def display_battle_title(attacker_name, defender_name)
	space_count = (180 - 56 - attacker_name.length + defender_name.length) / 2.0

	print "\n\n"
	print_colored_line([{color: :black, text: "*" * 180}], :white)
	line_details = []
	line_details << {color: :black, text: "*" * 10} 
	line_details << {color: :black, text: " " * space_count.to_i} 
	line_details << {color: :blue, text: "#{attacker_name} Versus #{defender_name}"}
	line_details << {color: :black, text: " " * space_count.round} 
	line_details << {color: :black, text: "*" * 10} 
	print_colored_line(line_details, :white)
	print_colored_line([{color: :black, text: "*" * 180}], :white)
end

def simulate_fight_summary(attacker_details, defender_details)
	display_battle_title(attacker_details[:name],defender_details[:name])

	print "#{defender_details[:name]} has #{defender_details[:hp]} Hit Points, and Magical Density of #{defender_details[:density][:rank]}\n"
	print "          They have #{defender_details[:density][:damage_reduction] - attacker_details[:density][:damage_reduction]} DR from being a higher rank\n"

	print "          Their #{defender_details[:armor][:name]} armor is "
	if defender_details[:armor][:bonus].to_i == 0
		print "non-magical granting damage reduction #{defender_details[:armor][:damage_reduction]}\n"
	else
		print "+#{defender_details[:armor][:bonus]} granting damage reduction #{defender_details[:armor][:damage_reduction] + defender_details[:armor][:bonus]}\n"
	end

	if defender_details[:shield] == nil
		print "          They do not have a shield\n"
	else
		print "          Their shield is "
		if defender_details[:shield][:bonus].to_i == 0
			print "non-magical granting damage reduction #{defender_details[:shield][:damage_reduction]}"
		else
			print "+#{defender_details[:shield][:bonus]} granting damage reduction #{defender_details[:shield][:damage_reduction] + defender_details[:shield][:bonus]}"
		end
		total_dr = defender_details[:armor][:damage_reduction] + defender_details[:armor][:bonus] + defender_details[:shield][:damage_reduction] + defender_details[:shield][:bonus]
		print "          Their total damage reduction is #{total_dr}\n"
	end

	if attacker_details[:turn_action][:attack_type] == :melee
		#if defender_details[:shield] == nil
			#print "          Their weapon skill is #{defender_details[:combat_skill][:ranks]}"
			#if defender_details[:weapon][:bonus].to_i == 0
				#print ", their weapon is non-magical, attacks against them have their TN increased by #{defender_details[:combat_skill][:static_bonus]}\n" 
			#else
				#total_bonus = defender_details[:combat_skill][:static_bonus]+ defender_details[:weapon][:bonus]
				#print ", their weapon is +#{defender_details[:weapon][:bonus]}, attacks against them have their TN increased by #{total_bonus}\n" 
			#end
		#else
		if defender_details[:shield]
			print "          Their weapon skill is #{defender_details[:combat_skill][:ranks]}"
			total_bonus = defender_details[:combat_skill][:static_bonus]+ defender_details[:weapon][:bonus].to_i + defender_details[:shield][:bonus].to_i
			if defender_details[:weapon][:bonus].to_i == 0
				print ", their weapon is non-magical, attacks against them have their TN increased by #{total_bonus}\n" 
			else
				print ", their weapon is +#{defender_details[:weapon][:bonus]}, attacks against them have their TN increased by #{total_bonus}\n" 
			end
		end
	end

	if defender_details[:turn_action][:dodge_dice] > 0
		if defender_details[:shield]
			total_bonus = defender_details[:shield][:bonus] + defender_details[:shield][:damage_reduction]
			print "          Their shield is +#{defender_details[:shield][:bonus]} reducing damage #{total_bonus} \n"
		end
		print "          They are spending #{defender_details[:turn_action][:dodge_dice]} dice to dodge each attack\n"
	else
		print "          They aren't deigning to dodge\n"
	end

	print "\n\n#{attacker_details[:name]} is attacking with #{attacker_details[:pronoun]} #{attacker_details[:weapon][:name]}. "
	print "#{attacker_details[:pronoun].capitalize} weapon adds #{attacker_details[:weapon][:base_damage_bonus]} damage"
	print " and #{attacker_details[:weapon][:typed_damage][:emotional]} dice of emotional damage" if attacker_details[:weapon][:typed_damage][:emotional]
	print " to each hit\n"

	print "          #{attacker_details[:pronoun].capitalize} weapon skill is #{attacker_details[:combat_skill][:ranks]}"
	if attacker_details[:weapon][:bonus].to_i == 0
		print ", #{attacker_details[:pronoun]} weapon is non-magical, attacks made have their TN decreased by #{attacker_details[:combat_skill][:static_bonus]}\n"
	else
		total_bonus = attacker_details[:combat_skill][:static_bonus] + attacker_details[:weapon][:bonus]
		print ", #{attacker_details[:pronoun]} weapon is +#{attacker_details[:weapon][:bonus]}, attacks made have their TN decreased by #{total_bonus}\n"
	end

	print "\n\n#{attacker_details[:name]} will roll #{attacker_details[:turn_action][:attack_actions].join(" and ")} dice each attack"
	tn_details = adjust_attack_tn(attacker_details, defender_details)
	print " and need to roll a #{tn_details[:attack_tn]} or higher\n"
	print "#{defender_details[:name]} will roll #{defender_details[:turn_action][:dodge_dice]} dice each turn"
	print " and need to roll a #{tn_details[:dodge_tn]} or higher\n"
	press_any_key
end

def calculate_deep_wound(attacker_details, defender_details, current_deep_wound, damage_dealt)
	magic_density_resistance = [3, 3 + defender_details[:density][:damage_reduction] - attacker_details[:density][:damage_reduction]].max
	deep_wound_inflicted = damage_dealt - magic_density_resistance
	return [current_deep_wound, deep_wound_inflicted].max
end

def display_attack_result(result, details)
	if result[:success]
		print "#{result[:message]} (Roll: #{result[:attack_roll]}, Physical Damage: #{result[:damage_breakdown][:physical_damage]}"
		print ", Emotional Damage: #{result[:damage_breakdown][:emotional]}" if result[:damage_breakdown][:emotional]
		print ")"
		print "             Remaining Hp #{details[:hp]}, Bleed #{details[:bleed]}, DW #{details[:deep_wound]}\n"
	else
		#print "#{result[:message]} (Roll: #{result[:attack_roll]})\n"
		line_details = []
		line_details << {color: :red, text: "    #{result[:message].capitalize}" } 
		#line_details << {color: :blue, text: "(Roll: #{result[:attack_roll]})"}

p result
		print_colored_line(line_details, :black)
		print "\n"
		print_die(1, :red)
		print_die(4, :black)
		print_die(9, :green)
		print_die(10, :green)
		print "\n\n"
	end


	#line_details = []
	#line_details << {color: :black, text: " " * 60} 
	#line_details << {color: :blue, text: "Round #{round}"}
	#line_details << {color: :black, text: " (#{current_hp}/#{max_hp})"}

	#print_colored_line(line_details, :white)

end

def simulate_fight(attacker_details, defender_details, display_action = true)
	debug_log("Simulate Fight between #{attacker_details[:name]} and #{defender_details[:name]}", {attacker: attacker_details.dup, defender: defender_details.dup})
	simulate_fight_summary(attacker_details, defender_details) if display_action

	details = {round: 1, swings: 0, hits: 0, hp: defender_details[:hp], bleed: 0, deep_wound: 0}

	while ( ( details[:hp] > 0 ) and ( (details[:deep_wound] * 2) < defender_details[:combat_pool]) )
		debug_log("Round #{details[:round]}", details)
		display_round_information(details[:round],details[:hp],defender_details[:hp]) if display_action

		attacker_details[:turn_action][:attack_actions].each do |attack_dice|
			result = simulate_an_attack(attacker_details, defender_details, attack_dice)

			details[:swings] += 1
			if result[:success]
				details[:hits] += 1
				details[:hp] -= result[:damage].to_i
				details[:bleed] += result[:bleed].to_i
				details[:deep_wound] = calculate_deep_wound(attacker_details, defender_details, details[:deep_wound], result[:damage])
			end

			display_attack_result(result, details) if display_action
		end

		bleed_details = handle_bleed(details[:bleed], defender_details)
		details[:hp] -= bleed_details[:bleed_damage]
		print "#{defender_details[:name]} bleeds for #{bleed_details[:bleed_damage]} points of damage\n" if bleed_details[:bleed_damage] > 0

		details[:round] += 1
		press_any_key if display_action and details[:round] % 5 == 0
	end

	if display_action
		if details[:hp] <= 0
			print "#{attacker_details[:name]} killed #{defender_details[:name]} in #{details[:round]} rounds\n"
		elsif deep_wound >= 8
			print "#{attacker_details[:name]} incapacitated #{defender_details[:name]} in #{details[:round]} rounds\n"
		else
			print "This shouldn't happen\n"
		end
		press_any_key
	end

	return details.clone
end

def calculate_average(attacker_details, defender_details, simulation_count=30)
	results = []
	simulation_count.times do
		results << simulate_fight(attacker_details, defender_details, false)
	end

	return {rounds: (results.sum { |i| i[:round] } / results.length.to_f), hit_percentage: 100 * (results.sum { |i| i[:hits] } / results.sum { |i| i[:swings] }.to_f) }
end







	#name, pronoun, hp, combat_pool
	#density {rank: 0-5, damage_reduction: 0-?}
	#armor {bonus: 0-5, damage_reduction: 1-6}
	#shield {bonus: 0-5, damage_reduction: 1-6}
	#combat_skill {ranks: 0-20, static_bonus: 0-5, bonus_dice: 1-5, attribute_dice: 1-10}
	#weapon {name: name, bonus: 0-5, damage_bonus: #, typed_damage: {emotional: 1-5, radiant: 1-5} } 
	#turn_action {attack_type: (:melee, :ranged, :magic, :nothing), dodge_dice: 0-10, attack_dice: 0-10, attacks_per_turn: 1-10}
#def simulate_fight(attacker_details, defender_details, display_action = true)
	

#olga = calculate_average("Olga",11,{attack_type: :melee, str_mod: 8, magic: 1})
#lysander = calculate_average("Lysander",10,{attack_type: :ranged, str_mod: 2, magic: 1, emotional: 4})

#p "Olga takes approximately #{olga[:rounds]} rounds with an average hit percentage #{olga[:hit_percentage].round(2)} %"
#p "Lysander takes approximately #{lysander[:rounds]} rounds with an average hit percentage #{olga[:hit_percentage].round(2)} %"
#exit

#Olga (tier 1) is hacking at a tier 2 mage with cloth armor
#Lysander (tier 1) is shooting at a tier 2 mage with cloth armor
#Stumpy (tier 1) is spellcasting at a tier 2 mage with cloth armor

#$deep_calculation = false

#3.times do
	##Olga   16 Str, 14 Dex, +1 Fey Axe, attack: 4+dex dice, 12+3(level)+dex combat dice
	##                                   attack: 11, 22 combat dice
	#fight_cultist("Olga",11,{attack_type: :melee, str_mod: 8, magic: 1})

	#press_any_key
#end

#3.times do
	#fight_cultist("Lysander",10,{attack_type: :ranged, str_mod: 2, magic: 1, emotional: 4})
#
	#press_any_key
#end

#p "Debug Notes"
#p $debug_notes

#p "Dice Probababilities"
#p $debug_dice_probability
#p $debug_dice_probability.tally.sort.map(&:last)





	#name, pronoun, hp, combat_pool
	#density {rank: 0-5, damage_reduction: 0-?}
	#armor {bonus: 0-5, damage_reduction: 1-6}
	#shield {bonus: 0-5, damage_reduction: 1-6}
	#combat_skill {ranks: 0-20, static_bonus: 0-5, bonus_dice: 1-5, attribute_dice: 1-10}
	#weapon {name: name, bonus: 0-5, base_damage_bonus: #, typed_damage: {emotional: 1-5, radiant: 1-5} } 
	#turn_action {attack_type: (:melee, :ranged, :magic, :nothing), dodge_dice: 0-10, attack_actions: [12, 6]}

#def simulate_fight(attacker_details, defender_details, display_action = true)
	##The mage (basically the cult leader) has +2 cloth armor and 5 DR from higher tier. 
	##He has plain cloth during your battle but it makes more sense his armor would have a strong enchantment. 
	##He has 24 health. He also has 16 combat pool and used 11 dice on his attack. 

monster_stats = {name: "Cultist Leader", pronoun: "his", hp: 24, combat_pool: 16, density: {rank: 3, damage_reduction: 7}, armor: {name: "cloth", bonus: 2, damage_reduction: 0}, combat_skill: {ranks: 2, static_bonus: 0, bonus_dice: 2, attribute_dice: 7}, weapon: {name: "Staff", bonus: 2, base_damage_bonus: 5, typed_damage: {}}}
monster_stats[:turn_action] = {attack_type: :nothing, dodge_dice: 4, attack_actions: [] }

olga_stats = {name: "Olga", pronoun: "her", hp: 16, combat_pool: 22, density: {rank: 2, damage_reduction: 2}, armor: {bonus: 0, damage_reduction: 2}, combat_skill: {ranks: 5, static_bonus: 0, bonus_dice: 5, attribute_dice: 7}, weapon: {name: "Fey Great Axe (Gary)", bonus: 1, base_damage_bonus: 10, typed_damage: {}}}
olga_stats[:turn_action] = {attack_type: :melee, dodge_dice: 0, attack_actions: [12, 10] }

lysander_stats = {name: "Lysander", pronoun: "his", hp: 12, combat_pool: 20, density: {rank: 2, damage_reduction: 2}, armor: {bonus: 0, damage_reduction: 1}, combat_skill: {ranks: 3, static_bonus: 0, bonus_dice: 3, attribute_dice: 8}, weapon: {name: "Wyd Bow of Mirth", bonus: 1, base_damage_bonus: 2, typed_damage: {emotional: 4}}}
lysander_stats[:turn_action] = {attack_type: :ranged, dodge_dice: 0, attack_actions: [11, 7] }

stumpy_stats = {name: "Stumpy", pronoun: "his", hp: 14, combat_pool: 18, density: {rank: 2, damage_reduction: 2}, armor: {bonus: 0, damage_reduction: 4}, combat_skill: {ranks: 5, static_bonus: 0, bonus_dice: 5, attribute_dice: 7}, weapon: {name: "Sacred Flame Cantrip", bonus: 0, base_damage_bonus: 3, typed_damage: {}}}
stumpy_stats[:turn_action] = {attack_type: :magic, dodge_dice: 0, attack_actions: [12, 6] }

simulate_fight(olga_stats.dup, monster_stats.dup, true)
simulate_fight(lysander_stats.dup, monster_stats.dup, true)
simulate_fight(stumpy_stats.dup, monster_stats.dup, true)


#calculation_result = []
#calculation_result << calculate_average(olga_stats.dup, monster_stats.dup)
#calculation_result[-1][:name] = "Olga"
#calculation_result << = calculate_average(lysander_stats.dup, monster_stats.dup)
#calculation_result[-1][:name] = "Lysander"

#calculation_result.each do |results|
	#p "#{results[:name]} takes approximately #{results[:rounds]} rounds with an average hit percentage #{results[:hit_percentage].round(2)} %"
#end
