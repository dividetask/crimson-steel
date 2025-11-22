
FULL_ROUND = 6
MOVE_ACTION = 4
MAIN_ACTION = 2
BONUS_ACTION = 1
FREE_ACTION = 0

SKILL_ATTRIBUTE = { bab: :dex,
	melee: :dex,						ranged: :dex, 					acrobatics: :dex, 			animal_handling: :cha,	appraisal: :int, 
	arcana: :int, 					athletics: :str, 				deception: :cha, 				disguise: :cha, 				druidic: :wis, 
	dungeoneering: :int, 		escape_artist: :dex, 		healing: :wis, 					history: :int, 					intimidate: :cha, 
	investigation: :int, 		linguistics: :int, 			nature: :int, 					nobility: :int, 				perception: :wis,
	perform_: :cha, 				persuasion: :cha,				planes: :int, 					profession_: :wis, 			religion: :int, 
	restricted_magic: :int, ride: :dex, 						larceny: :dex, 					sense_motive: :wis, 		slight_of_hand: :dex, 
	stealth: :dex, 					survival: :wis, 				use_magic_device: :cha }
#SKILL_NAME_SYMS = [['Strength', :str], ['Dexterity', :dex], ['Constitution', :con], ['Intelligence', :int], ['Wisdom', :wis], ['Charisma', :cha] ]
ATTRIBUTES = {str: 'Strength', dex: 'Dexterity', con: 'Constitution', int: 'Intelligence', wis: 'Wisdom', cha: 'Charisma'}

SKILL_BASE_TN = Hash.new(9).merge( { melee: 7, block: 7 })
CLASS_RESILIANCE = {barbarian: (1..20).to_a.map { |level| [level, 1 + (level / 2)] }.to_h}

module CharTools
  def weapons; self.items.select { |item| item.category == :weapon }; end
end

module CharMath
	def max_combat_pool
    dex_mod = half_mod(:dex)
    combat_pool_mod = (self.name == "Kraken") ? 2 : 1
    
    return dex_mod + combat_pool_mod * [1 + (self.level * 2  ).to_i, 10].min if self.density == 0
    return dex_mod + combat_pool_mod * [2 + (self.level * 2  ).to_i, 12].min if self.density == 1
    return dex_mod + combat_pool_mod * [2 + (self.level * 2  ).to_i, 15].min if self.density == 2
    return dex_mod + combat_pool_mod * [1 + (self.level * 1.5).to_i, 15].min if self.density == 3
    return dex_mod + combat_pool_mod * [1 + (self.level * 1  ).to_i, 15].min if self.density == 4
    return dex_mod + combat_pool_mod * [1 + (self.level * 0.5).to_i, 15].min if self.density == 5
  end

	def max_hp
  	return (self.con / 2) if density() == 0
    return (self.con * density() * 2) if self.role == :beast
    return (self.con * density())
	end

	def max_mana
		mana_per_level = {bard: 2, rogue: 2, cleric: 4}[self.klass]
		mana_per_level = 1 unless mana_per_level

  	return (mana_per_level * self.level) + (self.int / 4) if density() == 0
  	return (mana_per_level * self.level) + (self.int / 2) if density() == 1
    return (mana_per_level * self.level) + (self.int * (density() -1))
	end

  def density
  	return 0 if self.level <= 0
  	return 1 if self.level < 4
  	return 2 if self.level < 8
  	return 3 if self.level < 16
  	return 4 if self.level < 32
    return 5
  end
	def get_resiliance; density + @items.map { |item| item.category == :armor ? item.bonus : 0 }.sum + (CLASS_RESILIANCE[klass] || [])[level].to_i; end
	def get_disparity_dr; d = density; return d == 0 ? 0 : (d*5)-3;end
	def get_dr(attacker); @items.map { |item| item.get_dr }.sum + [0, get_disparity_dr - attacker.get_disparity_dr].max; end
	def get_base_dr; @items.map { |item| item.get_dr }.sum + [0, get_disparity_dr].max; end
end

module AttrMath
  def quarter_mod(attr); return self[attr] / 4; end
  def half_mod(attr); return self[attr] / 2; end
	def attr_dice(attr); return (half_mod(attr) % 5) + 4; end
	def attr_bonus(attr); return ((half_mod(attr) / 5) - 1); end
	def attr_result_mod(attr); tn = attr_tn_unbound(attr); return 9 - tn if tn > 9; return 4 - tn if tn < 4; return 0; end
	def attr_tn(attr); return [4,[9, attr_tn_unbound(attr)].min].max; end
	def attr_roll(attr); Check.new(ATTRIBUTES[attr], self.attr_dice(attr), attr_bonus(attr), {target: attr_tn(attr), result_mod: attr_result_mod(attr)}); end
  private
	def attr_tn_unbound(attr); return (9 - attr_bonus(attr)); end
end

module SaveMath
	def save_dice(attr); return attr_dice(attr); end
	def save_bonus(attr); return attr_bonus(attr); end
	def save_result_mod(attr); attr_result_mod(attr); end
	def save_tn(attr); return attr_tn(attr); end
	def save_roll(attr); return attr_roll(attr); end
  private
	def save_tn_unbound(attr); attr_tn_unbound(attr); end
end

module SkillMath
  def initiative(); return half_mod(:wis); end
  def skill_name(skill); return skill.to_s.split('_').join(' '); end

	def skill_ranks(skill); return ((self.level * (1 + self.skills[skill])) / 3); end
  def skill_attr_sym(skill); return SKILL_ATTRIBUTE[skill_category_name(skill) || skill]; end
	def skill_category_name(skill); SKILL_ATTRIBUTE.keys.find { |k| skill.to_s.start_with?(k.to_s) }; end
  def skill_attr_rank_sum(skill); return half_mod(skill_attr_sym(skill)) + skill_ranks(skill); end

	def skill_dice(skill); return (skill_attr_rank_sum(skill) % 5) + 6; end
	def skill_bonus(skill, tn_mod = 0); return ((skill_attr_rank_sum(skill) / 5) - 1) + tn_mod; end

	def skill_result_mod(skill, tn_mod = 0); tn = skill_tn_unbound(skill, tn_mod); return 9 - tn if tn > 9; return 4 - tn if tn < 4; return 0; end
	def skill_tn(skill, tn_mod = 0); return [4,[9, skill_tn_unbound(attr, tn_mod)].min].max; end
	def skill_roll(skill); Check.new(skill_name(skill), self.skill_dice(skill), skill_bonus(skill), {target: skill_tn(attr), result_mod: skill_result_mod(skill)}); end

  private
	def skill_tn_unbound(skill, tn_mod = 0); return (9 - (skill_bonus(skill) + tn_mod)); end
end

module AttackMath
	def attack_name; return weapon.get_attack_type.to_s; end
	def attack_dice; return skill_dice(:bab); end
	def attack_bonus(weapon, tn_mod = 0); return skill_bonus(:bab) + weapon.bonus + tn_mod; end

	def attack_result_mod(weapon, tn_mod = 0); tn = attack_tn_unbound(weapon, tn_mod); return 9 - tn if tn > 9; return 4 - tn if tn < 4; return 0; end
	def attack_tn(weapon, tn_mod = 0); return [4,[9, attack_tn_unbound(weapon, tn_mod)].min].max; end
	def attack_roll(weapon, tn_mod = 0)
    params = {target: attack_tn(weapon, tn_mod), result_mod: attack_result_mod(weapon, tn_mod)}
    Check.new(attack_name, self.attack_dice, attack_bonus(weapon, tn_mod), params)
  end

  private
	def attack_tn_unbound(weapon, tn_mod = 0); return (SKILL_BASE_TN[weapon.get_attack_type] - attack_bonus(weapon, tn_mod)); end
end

class Gender < Serializable
  attr_reader :gender  	# Can be read outside class, but not written
  private_class_method :new  # Makes .new private

  def initialize(gender); @gender = gender; end
  def self.male; new('M'); end
  def self.female; new('F'); end
  def self.m; new('M'); end
  def self.f; new('F'); end
  def self.it; new('?'); end
  def him_her; @gender == 'M' ? 'him' : (@gender == 'F' ? 'her' : 'it'); end
  def his_hers; @gender == 'M' ? 'his' : (@gender == 'F' ? 'hers' : 'its'); end
  def to_s; @gender == 'M' ? 'male' : (@gender == 'F' ? 'female' : 'sexless'); end
end

class CharacterStatus < Serializable
  attr_reader :character, :health_notes, :combat_pool, :main_actions, :mob_index

	def update_bleed(bleed_mod); @health_notes[:bleed] = [0, @health_notes[:bleed] += bleed_mod].max; end
  def bleed; @health_notes[:bleed]; end
	def reset_combat_dice; @combat_pool[:remaining], @combat_pool[:maximum] = @character.max_combat_pool - (2 * get_damage(MAJOR_DAMAGE));end
	def get_remaining_dice; @combat_pool[:remaining]; end
	def spend_dice(dice_count); @combat_pool[:remaining] -= dice_count; end
	def get_remaining_hp; return @health_notes[:maximum] - @health_notes[:damage_list].sum(&:amount); end
	def get_remaining_mana; return @character.max_mana - @health_notes[:mana_spent].to_i; end
	def get_saturation; return @health_notes[:saturation].to_i; end
  def get_damage(severity = nil); return @health_notes[:damage_list].select { |dmg| [nil, dmg.severity].include? severity}.sum(&:amount); end

	def turn_complete?; @main_actions == -1; end
	def new_initiative; @main_actions = 2; end
	def end_turn; @main_actions = -1; end
	def take_action(action_type, dice_spent = nil)
		if dice_spent
			@combat_pool[:remaining] -= dice_spent
		elsif action_type == FULL_ROUND
			@combat_pool[:remaining] -= 6
		elsif action_type == MOVE_ACTION or action_type == MAIN_ACTION
			@combat_pool[:remaining] -= 4
		end
	end
	def set_mob_index(mob_index); @mob_index = mob_index; end;
	def get_name; return @character.name unless @mob_index; return "#{@character.name} ##{@mob_index}"; end

  def initialize(char)
		@character = char
		@health_notes = {maximum: char.max_hp, bleed: 0, damage_list: []}
		@combat_pool = {remaining: char.max_combat_pool, maximum: char.max_combat_pool}
		@main_actions = 2
	end

	def add_damage(damage); @health_notes[:damage_list] << damage; @combat_pool[:remaining] -= (2 * damage.amount) if damage.severity == MAJOR_DAMAGE; end
	def cure_damage(amount, sev); rem = amount; @health_notes[:damage_list].each { |dmg| rem = dmg.cure_damage(rem,sev)};end
	def spend_mana(mana); @health_notes[:mana_spent] = @health_notes[:mana_spent].to_i + mana; end
	def add_mana_saturation(saturation); @health_notes[:saturation] = @health_notes[:saturation].to_i + saturation; end
  def method_missing(method, *args, &block); return @character.send(method, *args, &block) if @character.respond_to?(method); super; end
  def respond_to_missing?(method_name, include_private = false); @character.respond_to?(method_name, include_private) || super; end
end

class AbilityScores < Serializable
  attr_reader :str, :dex, :con, :int, :wis, :cha
  def initialize(str, dex, con, int, wis, cha); @str, @dex, @con, @int, @wis, @cha = str, dex, con, int, wis, cha; end
end

class Progression < Serializable
  attr_reader :klass, :level, :skills
  def initialize(klass, level, skills); @klass, @level, @skills =  klass, level, skills; end
end

class Identity < Serializable
  attr_reader :name, :gender, :role
	def initialize(name, gender, role); @name, @gender, @role = name, gender, role; end
end

class SpecialAbilities < Serializable
  attr_reader :name
	def initialize(name); @name = name; end
end

class CharacterSheet < Serializable
  include SkillMath
  include AttrMath
  include SaveMath
  include AttackMath

	include CharMath
  include CharTools
  attr_reader :id, :scores, :prog, :items, :special_abilities

  def initialize(id, scores, prog, items, special_abilities = []); @id, @scores, @prog, @items, @special_abilities = id, scores, prog, items, special_abilities; end
  def [](attribute); send(attribute); end

  def method_missing(method, *args, &block)
    [@id, @scores, @prog, @special_abilities].each { |obj| return obj.send(method, *args, &block) if obj.respond_to?(method) }; super
  end

  def respond_to_missing?(method_name, include_private = false)
    [@id, @scores, @prog, @special_abilities].any? { |obj| obj.respond_to?(method_name, include_private) } || super
  end
end
