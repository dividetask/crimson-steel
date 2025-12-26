require_relative 'character'

module CharacterHelpers
  def get_info(character)
#		sheet = CharacterSheet.new(character)

		#info = {name: sheet.name, player: sheet.player, deity: sheet.deity, race: sheet.race, level: sheet.level, tier: sheet.tier, bab: sheet.bab}
		#info[:combat_pool] = sheet.combat_pool
		#info[:damage_reduction] = sheet.damage_reduction
		#info[:damage_resiliance] = sheet.damage_resiliance
		#info[:hp_max] = "?"
		#info[:mana_max] = "?"
		#info[:mana_regen] = "?"
		#info[:full_klass] = sheet.full_klass

		#info[:ability_scores] = [
			#{name: "Strength", 			score: character["ability_scores"]["str"]},
			#{name: "Dexterity", 		score: character["ability_scores"]["dex"]},
			#{name: "Constitution", 	score: character["ability_scores"]["con"]},
			#{name: "Intelligence", 	score: character["ability_scores"]["int"]},
			#{name: "Wisdom", 				score: character["ability_scores"]["wis"]},
			#{name: "Charisma",		 	score: character["ability_scores"]["cha"]} ]

		#info[:ability_scores].map! do |ability_details|
			#ability_details[:half_score] = (ability_details[:score].to_i / 2)
			#ability_details[:skill_dice] = 6
			#ability_details[:skill_bonus] = "+0"
			#ability_details[:save_dice] = 6
			#ability_details[:save_bonus] = "+0"
			#ability_details
		#end

		#info[:skills] = [ {name: "Heal", ranks: 6, dice: 6, bonus: 2}, {name: "Sense Motive", ranks: 6, dice: 6, bonus: 2} ]

		#info
		CharacterSheet.new(character)
	end
end
