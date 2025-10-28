module ResetCharacters
	def self.overwrite_data
		data = DataStore.new('campaign')
		data.character_list = get_party
		data.character_list << get_krithrak_spider
		data.character_list << get_barbarian_3
		data.character_list << get_rogue_3
		data.save
	end

	def self.get_barbarian_3
		id = Identity.new("NPC Fighter 3", Gender.m, :NPC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(14, 	11, 	14, 	8, 		8, 		9) 
		skill_list = [:intimidate , :athletics].map { |s| [s, 1] }.to_h
		progression = Progression.new(:barbarian,	3, {melee: 3, ranged: 2}.merge(skill_list)) 
		equipment = [Equipment.new("Leather", :armor, :light, 0)]
		equipment << Equipment.new("Maul", :weapon, :maul, 0)
		equipment << Equipment.new("Javelin", :weapon, :javelin, 0)
		equipment << Equipment.new("Punch", :weapon, :punch, 0)
		CharacterSheet.new(id, stats, progression, equipment)
	end

	def self.get_rogue_3
		id = Identity.new("NPC Rogue 3", Gender.f, :NPC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(8, 		15, 	8, 		12, 	12, 	12) 

		skill_list = [:slight_of_hand, :deception, :persuasion, :sense_motive, :perform_juggle].map { |s| [s, 3] }.to_h
		progression = Progression.new(:rogue,	3, {melee: 1, ranged: 2}.merge(skill_list)) 
		equipment = [Equipment.new("Chain Shirt", :armor, :light, 0)]
		equipment << Equipment.new("Dagger", :weapon, :dagger, 0)
		equipment << Equipment.new("Shortbow", :weapon, :shortbow, 0)
		equipment << Equipment.new("Punch", :weapon, :punch, 0)
		CharacterSheet.new(id, stats, progression, equipment)
	end

	def self.get_party
		party = []

		id = Identity.new("Stumpy", Gender.m, :PC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(11,		13, 	14, 	13, 	15, 	10) 
		skill_list = [:survival, :religion, :sense_motive, :intimidate, :arcana].map { |s| [s, 2] }.to_h
		progression = Progression.new(:cleric,	3, {melee: 3, ranged: 2, healing: 3}.merge(skill_list)) 
		equipment = [Equipment.new('Breastplate', :armor, :medium, 0)]
		equipment << Equipment.new('Mirror Shield', :shield, :light_shield, 1)
		equipment << Equipment.new("Last Laugh Axe", :weapon, :battleaxe, 1, {bonus_damage: {emotional: 4}})
		equipment << Equipment.new('Longbow', :weapon, :longbow, 0)
		equipment << Equipment.new('Punch', :weapon, :punch, 0)
		party << CharacterSheet.new(id, stats, progression, equipment)


		id = Identity.new("Olga", Gender.f, :PC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(16, 	14, 	16, 	10, 	12, 	9) 
		skill_list = [:athletics, :sense_motive, :slight_of_hand, :stealth, :survival].map { |s| [s, 1] }.to_h
		progression = Progression.new(:barbarian,	3, {melee: 3, ranged: 2}.merge(skill_list)) 
		equipment = [Equipment.new("Leather", :armor, :light, 0)]
		equipment << Equipment.new("Fey Great Axe (Gary)", :weapon, :greataxe, 1)
		equipment << Equipment.new("Javelin", :weapon, :javelin, 0)
		equipment << Equipment.new("Punch", :weapon, :punch, 0)
		party << CharacterSheet.new(id, stats, progression, equipment)

		id = Identity.new("Lysander", Gender.m, :PC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(8, 		16, 	12, 	10, 	14, 	14) 
		skill_list = [:arcana, :stealth, :slight_of_hand, :deception, :persuasion, :larceny].map { |s| [s, 3] }.to_h
		progression = Progression.new(:rogue,	3, {melee: 1, ranged: 2}.merge(skill_list)) 
		equipment = [Equipment.new("Chain Shirt", :armor, :light, 0)]
		equipment << Equipment.new("Short Sword", :weapon, :short_sword, 0)
		equipment << Equipment.new("Wyd Bow of Mirth", :weapon, :longbow, 1, {bonus_damage: {emotional: 4}})
		equipment << Equipment.new("Punch", :weapon, :punch, 0)
		party << CharacterSheet.new(id, stats, progression, equipment)

		party
	end

	def self.get_cult_leaders
		id = Identity.new('Morgrath the Harbinger of Shadows', Gender.m, :boss) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(14,		12, 	12, 	16, 	16, 	12) 
		skill_list = [:restricted_magic, :deception, :persuasion, :stealth, :profession_cultist].map { |s| [s, 3] }.to_h
		progression = Progression.new(:cleric,	4, {melee: 1, ranged: 2}.merge(skill_list)) 

		equipment = [Equipment.new('+2 Robes', :armor, :clothing, 2)]
		equipment << Equipment.new("+2 Quarterstaff", :weapon, :quarterstaff, 2)
		equipment << Equipment.new("Punch", :weapon, :punch, 0)

		CharacterSheet.new(id, stats, progression, equipment)
	end

	def self.get_krithrak_spider
		id = Identity.new('Krithrak Spider', Gender.it, :beast) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(14,		16, 	8, 		1, 		10, 	2) 
		skill_list = [:stealth].map { |s| [s, 1] }.to_h
		progression = Progression.new(:vermin,	2, {melee: 2, ranged: 3}.merge(skill_list)) 

		equipment = [Equipment.new('Natural Armor', :armor, :natural, 1)]
		equipment << Equipment.new("Bite", :weapon, :bite, 1, {threshold: 7, poison: {potency: 5, effect: {severity: :minor, attr: :dex}}})
		equipment << Equipment.new("Web", :weapon, :web, 1, {entangle: {potency: 5}})

		CharacterSheet.new(id, stats, progression, equipment)
	end
end

