class StatusManager
  attr_reader :status_list, :character_disposition, :selected_sym, :selected_index
	#status_list is a <Hash>
		#each key is a <Symbol>
		#each value is a <Array>
			#each element in the <Array> is a <CharacterStatus>
	#character_disposition is a <Hash>
		#each key is a <Symbol>
		#character_disposition.keys Should equal status_list.keys
		#each value is a <Symbol>, values so far are :friendly, :hostile 

  #attr_reader :player_characters, :sheets, :status_list, :selected_sym, :selected_index

  def add_characters enemy_list
		@status_list = {}
		@status_list[:lysander] = [CharacterStatus.new(Character.get_lysanders_sheet)]
		@status_list[:olga] = [CharacterStatus.new(Character.get_olgas_sheet)]
		@status_list[:stumpy] = [CharacterStatus.new(Character.get_stumpys_sheet)]

		@character_disposition = @status_list.transform_values { :friendly }
		enemy_list.each { |sym, details| @status_list[sym] = Array.new(details[:count]) { CharacterStatus.new(details[:sheet]) } }
		@character_disposition = @character_disposition.merge(@status_list.transform_values { :enemy })
		@selected_sym, @selected_index = nil
	end

	def get_selected_status; @status_list[@selected_sym][@selected_index] if @selected_index; end
	def get_selected_name; @status_list[@selected_sym][@selected_index].character.name if @selected_index; end
	def get_rand_match(disposition); :selected_sym = @character_disposition.select { |k, v| v == disposition }.keys.sample; @selected_index = 0; end
	def get_rand_friendly; get_rand_match(:friendly); end;
	def get_first_enemy; get_rand_match(:hostile); end;
end

class CharacterStatus
  attr_reader :character, :health_notes, :combat_pool

	def update_bleed(bleed_mod); @health_notes[:bleed] = [0, @health_notes[:bleed] += bleed_mod].max; end
	def reset_combat_dice; @combat_pool[:remaining] = @combat_pool[:maximum]; end
	def get_remaining_dice; @combat_pool[:remaining]; end
	def spend_dice(dice_count); @combat_pool[:remaining] -= dice_count; end
	def get_remaining_hp; return @health_notes[:maximum] + @health_notes[:damage_list].sum(&:damage_amount); end

  def initialize(character)
		@character = character
		max_hp = RulesMath.get_max_hp(character)
		@health_notes = {maximum: max_hp, bleed: 0, damage_list: []}
		max_combat_pool = RulesMath.get_max_combat_pool(character)
		@combat_pool = {remaining: max_combat_pool, maximum: max_combat_pool}
	end

	def update_status(attack_details)
		update_bleed(attack_details.conditions[:bleed])
		@health_notes[:damage_list] << attack_details.damage_list.dup
	end
end

class CharacterStats
  attr_reader :character_type, :character_class, :level, :str, :dex, :con, :int, :wis, :cha, :skills

  def initialize(character_type, character_class, level, str, dex, con, int, wis, cha, skills)
		@character_type, @character_class, @level, @skills =  character_type, character_class, level, skills 
		@str, @dex, @con, @int, @wis, @cha = str, dex, con, int, wis, cha
	end

	def get_class_dr; return 1 + (@level / 4) if character_class == :barbarian; return 0; end
  def [](attribute); send(attribute); end
end

class Character
  attr_reader :name, :gender, :character_sheet, :equipment

  def initialize(name, gender, character_sheet, equipment)
		@name, @gender, @character_sheet, @equipment = name, gender, character_sheet, equipment
	end

	def get_resilience; return RulesMath.get_density(@character_sheet.level) + (@equipment.find { |obj| obj.category == :armor }&.bonus || 0); end

  def method_missing(method, *args, &block)
    if @character_sheet.respond_to?(method)
      @character_sheet.send(method, *args, &block)
    else
      super
    end
  end

	def self.get_olgas_sheet
  																	#class, 			level, 	str, 	dex, 	con, 	int, 	wis, 	cha
		stats = CharacterStats.new(:PC, :barbarian, 	3, 			16, 	14, 	16, 	10, 	12, 	9, {melee: 3, ranged: 2}) 
		armor = Equipment.new("Leather", :armor, :light, 0)
		axe = Equipment.new("Fey Great Axe (Gary)", :weapon, :greataxe, 1)
		javelin = Equipment.new("Javelin", :weapon, :javelin, 0)

		Character.new("Olga", Gender.f, stats, [armor, axe, javelin])
	end

	def self.get_lysanders_sheet
  																	#class, 			level, 	str, 	dex, 	con, 	int, 	wis, 	cha
		stats = CharacterStats.new(:PC, :rogue, 			3, 			8, 		16, 	12, 	10, 	14, 	14, {melee: 1, ranged: 2, arcane: 3})
		armor = Equipment.new('Chain Shirt', :armor, :light, 0)
		bow = Equipment.new("Wyd Bow of Mirth", :weapon, :longbow, 1, {bonus_damage: {emotional: 4}})

		Character.new("Lysander", Gender.m, stats, [armor, bow])
	end

	def self.get_stumpys_sheet
  																	#class, 		level, 	str, 	dex, 	con, 	int, 	wis, 	cha
		stats = CharacterStats.new(:PC, :cleric, 		3, 			11,		13, 	14, 	13, 	15, 	10, {melee: 3, ranged: 1, heal: 3})
		armor = Equipment.new('Breastplate', :armor, :medium, 0)
		shield = Equipment.new('Mirror Shield', :shield, :light_shield, 1)
		axe = Equipment.new("Last Laugh Axe", :weapon, :battleaxe, 1, {bonus_damage: {emotional: 4}})

		Character.new("Stumpy", Gender.m, stats, [armor, shield, axe])
	end

	def self.get_cult_leaders_sheet
  																		#class, 	level, 	str, 	dex, 	con, 	int, 	wis, 	cha
		stats = CharacterStats.new(:boss, :cleric, 	4, 			14,		12, 	12, 	16, 	16, 	12, {melee: 1, ranged: 2, restricted: 3})
		armor = Equipment.new('+2 Robes', :armor, :clothing, 2)
		weapon = Equipment.new("+2 Quarterstaff", :weapon, :quarterstaff, 2)

		Character.new("Morgrath the Harbinger of Shadows", Gender.m, stats, [armor, weapon])
	end

	def self.get_medium_spider
  																			#class, 	level, 	str, 	dex, 	con, 	int, 	wis, 	cha
		stats = CharacterStats.new(:beast, :vermin, 	2, 			14,		16, 	8, 		1, 		10, 	2, {melee: 2, ranged: 3, stealth: 1})
		armor = Equipment.new('Natural Armor', :armor, :natural, 1)
		bite = Equipment.new("Bite", :weapon, :bite, 1, {threshold: 7, poison: {potency: 5, effect: {severity: :minor, attr: :dex}}})
		web = Equipment.new("Web", :weapon, :web, 1, {entangle: {potency: 5}})

		Character.new("Medium Spider", Gender.it, stats, [armor, bite, web])
	end
end
