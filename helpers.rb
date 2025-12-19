module CharacterHelpers
  def load_json(filename)
    file_path = File.join(settings.root, 'data', filename)
    JSON.parse(File.read(file_path)) if File.exist?(file_path)
  end

	def get_tier_map(rules)
		tier = 0
		tier_lookup = (1..rules["advancement"]["tier"].last).to_a.map do |level|
			tier = tier + 1 if rules["advancement"]["tier"][tier] <= level
			[level, tier]
		end
		tier_lookup.to_h
	end

	def get_bab(character, rules)
		bab_increases = character["classes"].map do |klass|
			bab_adv_rate = rules["class_advancement"][klass["class"]]["bab"]
			bab_mod = rules["advancement"]["competency"]["bab_ranks_per_level"][bab_adv_rate]
			(klass["level"].to_f * bab_mod[0].to_f / bab_mod[1].to_f).to_i
		end
		bab_increases.sum
	end

	def get_combat_pool(character, tier, level, rules)
		pool_math = rules["advancement"]["competency"]["combat_pool"][tier]
		combat_pool = pool_math["base"] + (pool_math["inc"] * level)
		combat_pool = pool_math["max"] if combat_pool > pool_math["max"]
		combat_pool
	end

  def get_info(character)
		rules = load_json('rules.json')

		info = {name: character["name"], player: character["player"]}
		info[:deity] = character["deity"]
		info[:race] = character["race"][0]
		info[:race] << " #{character["race"][1]}" if character["race"][1]
		info[:level] = character["classes"].map { |klass| klass["level"].to_i }.sum
		info[:tier] = character["tier"] || get_tier_map(rules)[info[:level]]
		info[:bab] = get_bab(character, rules)
		info[:combat_pool] = get_combat_pool(character, info[:tier], info[:level], rules)
		info[:damage_reduction] = rules["tier"]["damage_reduction"][info[:tier]]  	#Needs to add for armor
		info[:damage_resiliance] = rules["tier"]["damage_resiliance"][info[:tier]]  #Needs to add for armor
		info[:hp_max] = "?"
		info[:mana_max] = "?"
		info[:mana_regen] = "?"
		info[:full_klass] = character["classes"].map { |klass| "#{klass["class"]} #{klass["level"]}" }.join(', ')

		info[:ability_scores] = [
			{name: "Strength", 			score: character["ability_scores"]["str"]},
			{name: "Dexterity", 		score: character["ability_scores"]["dex"]},
			{name: "Constitution", 	score: character["ability_scores"]["con"]},
			{name: "Intelligence", 	score: character["ability_scores"]["int"]},
			{name: "Wisdom", 				score: character["ability_scores"]["wis"]},
			{name: "Charisma",		 	score: character["ability_scores"]["cha"]} ]

		info[:ability_scores].map! do |ability_details|
			ability_details[:half_score] = (ability_details[:score].to_i / 2)
			ability_details[:skill_dice] = 6
			ability_details[:skill_bonus] = "+0"
			ability_details[:save_dice] = 6
			ability_details[:save_bonus] = "+0"
			ability_details
		end

		info[:skills] = [ {name: "Heal", ranks: 6, dice: 6, bonus: 2}, {name: "Sense Motive", ranks: 6, dice: 6, bonus: 2} ]

		info
	end
end
