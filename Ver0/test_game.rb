require_relative 'declarations'

require_relative 'basic_math'
require_relative 'rules'
require_relative 'character'
require_relative 'combat'
require_relative 'dice'
require_relative 'display'
require_relative 'run_tests'



RunTests.test_cultist

exit
cultist = Character.get_cult_leaders_sheet
lysander = Character.get_lysanders_sheet
olga = Character.get_olgas_sheet
basic_combat = BasicCombat.new(lysander, cultist, true)
basic_combat.simulate_combat
exit

cultist = Character.get_cult_leaders_sheet
lysander = Character.get_lysanders_sheet
olga = Character.get_olgas_sheet
basic_combat = BasicCombat.new(lysander, cultist, true)

goals = [:no_damage, :miss, :damage]
goals.each do |goal|
	if goal == :no_damage
		Roll.cheat( ([9] * 3) + ([4] * 20))
		p "Should be no damage"
	elsif goal == :damage
		Roll.cheat( ([9] * 5) + ([4] * 20))
		p "Should be 1 damage"
	elsif goal == :miss
		Roll.cheat( ([9] * 1) + ([4] * 20))
		p "Should be miss"
	end
	last_attack_log = basic_combat.combat_tracker.handle_attack(10, 4)
	#Display.display_attack_1 last_attack_log
	Display.display_attack last_attack_log
	Display.press_any_key
end

exit

cultist = Character.get_cult_leaders_sheet
lysander = Character.get_lysanders_sheet
olga = Character.get_olgas_sheet
basic_combat = BasicCombat.new(lysander, cultist, true)
basic_combat.simulate_combat
exit

#dice = Roll.new(10)
#Display.draw_dice(dice)

cultist = Character.get_cult_leaders_sheet
lysander = Character.get_lysanders_sheet
olga = Character.get_olgas_sheet
#basic_combat = BasicCombat.new(olga, cultist, 2, true)
basic_combat = BasicCombat.new(lysander, cultist, 1, true)
attack_log = basic_combat.combat_tracker.handle_attack(10, 2)

Display.display_attack attack_log
exit

dice = {attack: Roll.new(11), dodge: Roll.new(4)}
Display.draw_dice(dice)
exit

    numbers = [3, 5, 6, 2, 4, 1, 4, 8, 1, 10]
Display.display_round_information(10, 8, 15)
Display.display_attack numbers, 7

exit

#olga = Character.get_olgas_sheet
#lysander = Character.get_lysanders_sheet
#cultist = Character.get_cult_leaders_sheet

#simulate_fight(olga, cultist, true)

olga = Character.get_olgas_sheet
cultist = Character.get_cult_leaders_sheet
combat_tracker = BasicCombat.new(olga, cultist, 4, true)
combat_tracker.simulate_round
