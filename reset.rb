RANKS_MAX = 3
RANKS_MOD = 2
RANKS_MIN = 1

RANKS_PER_LEVEL = {RANKS_MAX => 5 / 3.0, RANKS_MOD => 1, RANKS_MIN => 2 / 3.0 }

module ResetCharacters
	def self.overwrite_data
		data = DataStore.new('campaign')
		data.character_list = get_party
		data.character_list << get_theron
		data.character_list << get_kraken
		data.character_list << get_pirate_1
    data.status_list = data.character_list.map { |char| CharacterStatus.new(char) }
		data.save
	end

	def self.get_kraken
		id = Identity.new("Kraken", Gender.it, :beast) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(28, 	15, 	21, 	5, 		12, 		6) 
		skill_list = [:athletics, :perception].map { |s| [s, RANKS_MIN] }.to_h
		progression = Progression.new(:beast,	10, {bab: RANKS_MIN}.merge(skill_list)) 
		equipment = [Equipment.new('Natural Armor', :armor, :natural, 3)]
		equipment << Equipment.new("Bite", :weapon, :bite, 3, {threshold: 5})
		equipment << Equipment.new("Tentacle", :weapon, :slam, 3, {threshold: 3, poison: {potency: 5, effect: {severity: :minor, attr: :int}}})

		CharacterSheet.new(id, stats, progression, equipment)
	end

	#def self.get_werewolf
		#id = Identity.new("NPC Werewolf 4", Gender.m, :NPC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		#stats = AbilityScores.new(16, 	13, 	16, 	8, 		12, 		8) 
		#skill_list = [:intimidate , :athletics, :perception, :survival].map { |s| [s, RANKS_MAX] }.to_h
		#progression = Progression.new(:barbarian,	4, {bab: RANKS_MAX}.merge(skill_list)) 
		#equipment = [Equipment.new("Leather", :armor, :light, 0)]
		#equipment << Equipment.new("Sword", :weapon, :short_sword, 0)
		#equipment << Equipment.new("Javelin", :weapon, :javelin, 0)
		#equipment << Equipment.new("Natural Attack", :weapon, :bite, 2)
		#CharacterSheet.new(id, stats, progression, equipment)
	#end

	#def self.get_werewolf_alpha
		#id = Identity.new("NPC Alpha Werewolf 8", Gender.m, :NPC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		#stats = AbilityScores.new(20, 	14, 	19, 	12, 	14, 	10) 
		#skill_list = [:intimidate , :athletics, :perception, :survival].map { |s| [s, RANKS_MAX] }.to_h
		#progression = Progression.new(:barbarian,	4, {bab: RANKS_MAX}.merge(skill_list)) 
		#equipment = [Equipment.new("Leather", :armor, :light, 0)]
		#equipment << Equipment.new("Sword", :weapon, :short_sword, 0)
		#equipment << Equipment.new("Javelin", :weapon, :javelin, 0)
		#equipment << Equipment.new("Natural Attack", :weapon, :bite, 3)
		#CharacterSheet.new(id, stats, progression, equipment)
	#end

	#def self.get_barbarian_3
		#id = Identity.new("NPC Fighter 3", Gender.m, :NPC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		#stats = AbilityScores.new(14, 	11, 	14, 	8, 		8, 		9) 
		#skill_list = [:intimidate , :athletics].map { |s| [s, RANKS_MAX] }.to_h
		#progression = Progression.new(:barbarian,	3, {bab: RANKS_MAX}.merge(skill_list)) 
		#equipment = [Equipment.new("Leather", :armor, :light, 0)]
		#equipment << Equipment.new("Maul", :weapon, :maul, 0)
		#equipment << Equipment.new("Javelin", :weapon, :javelin, 0)
		#equipment << Equipment.new("Punch", :weapon, :punch, 0)
		#CharacterSheet.new(id, stats, progression, equipment)
	#end

	#def self.get_rogue_3
		#id = Identity.new("NPC Rogue 3", Gender.f, :NPC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		#stats = AbilityScores.new(8, 		15, 	8, 		12, 	12, 	12) 
		#skill_list = [:slight_of_hand, :deception, :persuasion, :sense_motive, :perform_juggle].map { |s| [s, RANKS_MAX] }.to_h
		#progression = Progression.new(:rogue,	3, {bab: RANKS_MOD}.merge(skill_list)) 
		#equipment = [Equipment.new("Chain Shirt", :armor, :light, 0)]
		#equipment << Equipment.new("Dagger", :weapon, :dagger, 0)
		#equipment << Equipment.new("Shortbow", :weapon, :shortbow, 0)
		#equipment << Equipment.new("Punch", :weapon, :punch, 0)
		#CharacterSheet.new(id, stats, progression, equipment)
	#end

	def self.get_pirate_1
		id = Identity.new("NPC Pirate 1", Gender.m, :NPC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(15, 	14, 	15, 	10, 	12, 	8) 
		skill_list = [:intimidate, :profession_sailor, :athletics].map { |s| [s, RANKS_MAX] }.to_h
		progression = Progression.new(:rogue,	1, {bab: RANKS_MOD}.merge(skill_list)) 
		equipment = [Equipment.new("Leather", :armor, :light, 0)]
		equipment << Equipment.new("Rapier", :weapon, :rapier, 0, true)
		equipment << Equipment.new("Shortbow", :weapon, :shortbow, 0)
		equipment << Equipment.new("Punch", :weapon, :punch, 0)
		CharacterSheet.new(id, stats, progression, equipment)
	end

	def self.get_theron
		id = Identity.new("Theron", Gender.m, :NPC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(17, 	17, 	12, 	12, 	15, 	9) 
		skill_list = [:intimidate, :heal, :druidic, :perception, :stealth, :sense_motive].map { |s| [s, RANKS_MAX] }.to_h
		progression = Progression.new(:ranger,	8, {bab: RANKS_MOD}.merge(skill_list)) 
		equipment = [Equipment.new("Chain Shirt", :armor, :light, 2)]
		equipment << Equipment.new("Dagger", :weapon, :dagger, 0)
		equipment << Equipment.new("Longbow", :weapon, :longbow, 2, {bonus_damage: {heart_seeker: 4}})
		equipment << Equipment.new("Punch", :weapon, :punch, 0)
		CharacterSheet.new(id, stats, progression, equipment)
	end

	def self.get_party
		party = []

		id = Identity.new("Stumpy", Gender.m, :PC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(12,		14, 	17, 	14, 	18, 	11) 
		skill_list = [:heal, :sense_motive, :arcana].map { |s| [s, RANKS_MAX] }.to_h
		skill_list = [:survival, :intimidate, :perception].map { |s| [s, RANKS_MOD] }.to_h.merge(skill_list)
		progression = Progression.new(:cleric,	4, {bab: RANKS_MOD}.merge(skill_list)) 
		equipment = [Equipment.new('Breastplate', :armor, :medium, 0)]
		equipment << Equipment.new('Mirror Shield', :shield, :light_shield, 1, {}, true)
		equipment << Equipment.new("Last Laugh Axe", :weapon, :battleaxe, 1, {bonus_damage: {emotional: 4}})
		equipment << Equipment.new('Longbow', :weapon, :longbow, 0)
		equipment << Equipment.new('Punch', :weapon, :punch, 0)
    equipment << ConjuredEquipment.new('Shield of Faith', :shield, :light_shield, 1, {needs_dice: true, block_allies: true, skill: :heal})
    equipment << ConjuredEquipment.new('Spirtual Weapon', :weapon, :rapier, 1, {needs_dice: false, skill: :heal})
    special_abilities = [SpecialAbilities.new('Cleave')]

		party << CharacterSheet.new(id, stats, progression, equipment, special_abilities)

		id = Identity.new("Olga", Gender.f, :PC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(19, 	17, 	17, 	11, 	13, 	10)
		skill_list = [:athletics, :survival].map { |s| [s, RANKS_MAX] }.to_h
		skill_list = [:sense_motive, :stealth].map { |s| [s, RANKS_MOD] }.to_h.merge(skill_list)

		progression = Progression.new(:barbarian,	4, {bab: RANKS_MAX}.merge(skill_list))
		equipment = [Equipment.new("+1 Leather", :armor, :light, 1)]
		equipment << Equipment.new("Fey Great Axe (Gary)", :weapon, :greataxe, 2)
		equipment << Equipment.new("Javelin", :weapon, :javelin, 0)
		equipment << Equipment.new("Punch", :weapon, :punch, 0)
    equipment << ConjuredEquipment.new('Ring of Parry', :weapon, :greataxe, 2, {needs_dice: false, parry: true, skill: :bab})
    special_abilities = [SpecialAbilities.new('Primal Tenacity')]
    special_abilities << SpecialAbilities.new('Cleave')
    special_abilities << SpecialAbilities.new('Uncanny Dodge')

		party << CharacterSheet.new(id, stats, progression, equipment, special_abilities)

		id = Identity.new("Lysander", Gender.m, :PC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(9, 		19, 	13, 	14, 	15, 	15) 
		skill_list = [:stealth, :slight_of_hand, :deception, :persuasion, :larceny, :arcana, :perception].map { |s| [s, RANKS_MAX] }.to_h
		progression = Progression.new(:rogue,	4, {bab: RANKS_MOD}.merge(skill_list)) 
		equipment = [Equipment.new("+1 Leather Armor", :armor, :light, 1)]
		equipment << Equipment.new("Short Sword", :weapon, :short_sword, 0)
		equipment << Equipment.new("Wyd Bow of Mirth", :weapon, :longbow, 1, {bonus_damage: {emotional: 4}})
		equipment << Equipment.new("Punch", :weapon, :punch, 0)
    special_abilities = [SpecialAbilities.new('Danger Sense')]
    special_abilities << SpecialAbilities.new('Sneak Attack')
		party << CharacterSheet.new(id, stats, progression, equipment, special_abilities)

#(M) Cinnamon buns
		id = Identity.new("Cottonballs", Gender.m, :PC) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		stats = AbilityScores.new(11, 	18, 	14, 	12, 	13, 	18) 
		skill_list = [:stealth, :slight_of_hand, :deception, :persuasion, :larceny, :arcana, :perception].map { |s| [s, RANKS_MAX] }.to_h
		progression = Progression.new(:rogue,	4, {bab: RANKS_MOD}.merge(skill_list)) 
		equipment = [Equipment.new("+1 Leather Armor", :armor, :light, 1)]
		equipment << Equipment.new("Short Sword", :weapon, :short_sword, 0)
		equipment << Equipment.new("Wyd Bow of Mirth", :weapon, :longbow, 1, {bonus_damage: {emotional: 4}})
		equipment << Equipment.new("Punch", :weapon, :punch, 0)
    special_abilities = [SpecialAbilities.new('Danger Sense')]
    special_abilities << SpecialAbilities.new('Sneak Attack')
		party << CharacterSheet.new(id, stats, progression, equipment, special_abilities)

		party
	end

	#def self.get_cult_leaders
		#id = Identity.new('Morgrath the Harbinger of Shadows', Gender.m, :boss) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		#stats = AbilityScores.new(14,		12, 	12, 	16, 	16, 	12) 
		#skill_list = [:restricted_magic, :deception, :persuasion, :stealth, :profession_cultist].map { |s| [s, 3] }.to_h
		#progression = Progression.new(:cleric,	4, {melee: 1, ranged: 2}.merge(skill_list)) 

		#equipment = [Equipment.new('+2 Robes', :armor, :clothing, 2)]
		#equipment << Equipment.new("+2 Quarterstaff", :weapon, :quarterstaff, 2)
		#equipment << Equipment.new("Punch", :weapon, :punch, 0)

		#CharacterSheet.new(id, stats, progression, equipment)
	#end

	#def self.get_krithrak_spider
		#id = Identity.new('Krithrak Spider', Gender.it, :beast) 
  														#str, dex, 	con, 	int, 	wis, 	cha
		#stats = AbilityScores.new(14,		16, 	8, 		1, 		10, 	2) 
		#skill_list = [:stealth].map { |s| [s, 1] }.to_h
		#progression = Progression.new(:vermin,	2, {melee: 2, ranged: 3}.merge(skill_list)) 

		#equipment = [Equipment.new('Natural Armor', :armor, :natural, 1)]
		#equipment << Equipment.new("Bite", :weapon, :bite, 1, {threshold: 7, poison: {potency: 5, effect: {severity: :minor, attr: :dex}}})
		#equipment << Equipment.new("Web", :weapon, :web, 1, {entangle: {potency: 5}})

		#CharacterSheet.new(id, stats, progression, equipment)
	#end
end

