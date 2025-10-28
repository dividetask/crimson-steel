class DefensiveEquipment
  attr_reader :name, :equimpent_type, :bonus, :damage_reduction  	# Can be read outside class, but not written

  def initialize(name, equimpent_type, bonus, damage_reduction)
		@name, @equimpent_type, @bonus, @damage_reduction = name, equimpent_type, bonus, damage_reduction
  end

  def get_dr
  	return @bonus + @damage_reduction
  end
end

class DamageFormula
  attr_reader :name, :static_amount, :number_of_dice  	# Can be read outside class, but not written

  def initialize(name, static_amount, number_of_dice)
		@name = name
		@static_amount = static_amount
		@number_of_dice = number_of_dice
  end
end

class Weapon
	# name: <STRING>, bonus: <INT>, main_damage: <DamageFormula>, bonus_damage_list: <DamageFormula>
  attr_reader :name, :weapon_type, :bonus, :bonus_damage_list  	# Can be read outside class, but not written

  def initialize(name, weapon_type, bonus, bonus_damage_list = nil)
    @name, @weapon_type, @bonus = name, weapon_type, bonus
		@bonus_damage_list = bonus_damage_list || []
  end
end

class Damage
  attr_reader :total, :damage_reduction, :weapon_base_damage, :physical, :rolled_typed_damage, :typed_damage, :bleed, :deep_wound, :damage_rolls, :was_success

  def initialize
    @total = @damage_reduction = @weapon_base_damage = @physical = @rolled_typed_damage = @typed_damage = @bleed = @deep_wound = 0
    @was_success = false
    @damage_rolls = {}
  end

  def set(key, value); instance_variable_set("@#{key}", value); end
  def increment(key, amount = 1); current = instance_variable_get("@#{key}") || 0; instance_variable_set("@#{key}", current + amount); end
  #def add_roll(key, value) = (@damage_rolls ||= {})[key] = value
	def add_roll(key, value); (@damage_rolls ||= {})[key] = value; end
end

class Gender
  attr_reader :gender  	# Can be read outside class, but not written
  private_class_method :new  # Makes .new private

  def initialize(gender); @gender = gender; end
  def self.male; new('M'); end
  def self.female; new('F'); end
  def self.m; new('M'); end
  def self.f; new('F'); end
  def him_her; @gender == 'M' ? 'him' : (@gender == 'F' ? 'her' : 'it'); end
  def his_hers; @gender == 'M' ? 'his' : (@gender == 'F' ? 'hers' : 'its'); end
end

class CharacterStats
  attr_reader :character_class, :level, :str, :dex, :con, :int, :wis, :cha, :melee, :ranged, :magic  	# Can be read outside class, but not written

  def initialize(character_class, level, str, dex, con, int, wis, cha, melee, ranged, magic = 0)
		@character_class, @level, @str, @dex, @con, @int, @wis, @cha, @melee, @ranged, @magic = character_class, level, str, dex, con, int, wis, cha, melee, ranged, magic
	end

  def [](attribute)
    send(attribute)
  end
end

class Character
  attr_reader :name, :gender, :character_sheet, :armor, :shield, :weapon, :spell, :action_plan  	# Can be read outside class, but not written

  def initialize(name, gender, character_sheet, armor, shield, weapon, spell, action_plan)
		@name, @gender, @character_sheet, @armor, @shield, @weapon, @spell, @action_plan = name, gender, character_sheet, armor, shield, weapon, spell, action_plan
	end

	def self.get_olgas_sheet
  														#class, 			level, 	str, 	dex, 	con, 	int, 	wis, 	cha, 	melee, 	ranged, magic = 0)
		stats = CharacterStats.new(:barbarian, 	3, 			16, 	14, 	16, 	10, 	12, 	9, 		3, 			2)
		armor = DefensiveEquipment.new('Leather', :armor, 0, 1)
		weapon = Weapon.new("Fey Great Axe (Gary)", :greataxe, 1, nil)

		Character.new("Olga", Gender.f, stats, armor, nil, weapon, nil, :melee_max_dice)
	end

	def self.get_lysanders_sheet
  														#class, 			level, 	str, 	dex, 	con, 	int, 	wis, 	cha, 	melee, 	ranged, magic = 0)
		stats = CharacterStats.new(:rogue, 			3, 			8, 		16, 	12, 	10, 	14, 	14, 	1, 			2, 			3)
		armor = DefensiveEquipment.new('Chain Shirt', :armor, 0, 1)
		weapon = Weapon.new("Wyd Bow of Mirth", :longbow, 1, [DamageFormula.new(:emotional, 0, 4)])

		Character.new("Lysander", Gender.m, stats, armor, nil, weapon, nil, :ranged_mox_dice)
	end

	def self.get_stumpys_sheet
  														#class, 			level, 	str, 	dex, 	con, 	int, 	wis, 	cha, 	melee, 	ranged, magic = 0)
		stats = CharacterStats.new(:cleric, 		3, 			11,		13, 	14, 	13, 	15, 	10, 	3, 			1, 			3)
		armor = DefensiveEquipment.new('Breastplate', :armor, 0, 4)
		shield = DefensiveEquipment.new('Mirror Shield', :shield, 1, 1)
		weapon = Weapon.new("Last Laugh Axe", :battleaxe, 1, [DamageFormula.new(:emotional, 0, 4)])
		sacred_flame = nil

		Character.new("Stumpy", Gender.m, stats, armor, shield, weapon, sacred_flame, :magic_max_dice)
	end

	def self.get_cult_leaders_sheet
  														#class, 			level, 	str, 	dex, 	con, 	int, 	wis, 	cha, 	melee, 	ranged, magic = 0)
		stats = CharacterStats.new(:boss, 			4, 			14,		12, 	12, 	16, 	16, 	12, 	1, 			2, 			3)
		armor = DefensiveEquipment.new('+2 Robes', :armor, 2, 0)
		weapon = Weapon.new("+2 Quarterstaff", :staff, 2, nil)
		sacred_flame = nil

		Character.new("Morgrath the Harbinger of Shadows", Gender.m, stats, armor, nil, weapon, sacred_flame, :dodge_4)
	end
end
