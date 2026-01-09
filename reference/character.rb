require_relative 'tools'

class Compendium
  attr_reader :data

  def initialize; @data = Tools.load_json('compendium.json'); end
	def format_name(ability_name); return ability_name.gsub('_', ' ').split(' ').map(&:capitalize).join(' '); end
	def ability(entry); return @data["abilities"][entry.to_s]; end
end

class Abilities
  attr_reader :rules, :level, :ability_list
	def initialize(rules, level, ability_list); @rules, @level, @ability_list = rules, level, ability_list; end
	def adjust(skill); return skill; end

	def self.list(klass,level)
		return @rules["reference"]["class_abilities"][klass].select { |min_level, list| level >= min_level.to_i }.values.flatten
	end
end

class Skill
  attr_reader :rules, :type, :name, :group, :ranks, :modifiers

	def initialize(rules, type, name)
		@rules, @type, @name, @ranks, @modifiers = rules, type, name, 0, {}
		@group = Skill.skill_group(rules, name)
	end

	def add_modifier(key, value); @modifiers[key] = value if @modifiers[key] == nil or value > @modifiers[key]; end
	def inc_ranks(klass, level); @ranks = @ranks + (adv_multiplier(skill_adv_rate(klass)) * level).to_i; end


	#def self.bab_ranks(rules, klass, level); return (adv_multiplier(rules, bab_adv_rate(rules, klass)) * level).to_i; end
	#def self.bab_adv_rate(rules, klass); return rules["class_advancement"][klass]["bab"]; end

	#def self.skill_ranks(rules, klass, skill, level); return (adv_multiplier(rules, skill_adv_rate(rules, klass, skill)) * level).to_i; end
	#def self.is_class_skill?(rules, klass, skill); return rules['reference']['class_skills'][klass].include?(skill_group(rules, skill)); end
	#def self.is_slow_skill?(rules, skill); return rules['reference']['slow_skills'].include?(skill_group(rules, skill)); end
	#def self.skill_adv_rate(rules, klass, skill); return is_class_skill?(rules, klass, skill) ? 3 : is_slow_skill?(rules, skill) ? 1 : 2; end

	#def self.skill_group(rules, skill); return skill_list(rules).find { |group, attr| skills_match?(group, skill) }[0]; end
	#def self.skill_attr(rules, skill); return skill_list(rules)[skill_group(rules, skill)].to_sym; end
	#def self.skill_list(rules); rules["reference"]["skill_list"]; end
	#def self.skills_match?(group, skill); group == skill.to_s || (group.end_with?('_') && skill.to_s.start_with?(group)); end

	#def self.dice(rules, total_ranks); return eval(rules['reference']['skill_dice'].dup.gsub!('ranks', total_ranks.to_s)); end
	#def self.bonus(rules, total_ranks); return eval(rules['reference']['skill_bonus'].dup.gsub!('ranks', total_ranks.to_s)); end

	def self.clean_skill_name(skill); return skill.gsub('_', ' ').split(' ').map(&:capitalize).join(' '); end
	private
	#def self.adv_multiplier(rules, adv_rate); rules['reference']['skill_advancement'][adv_rate - 1].map { |i| i.to_f}.inject(:*).to_i; end
	def adv_multiplier(adv_rate); @rules['reference']['skill_advancement'][adv_rate - 1].map { |i| i.to_f}.inject(:*).to_i; end
	def skill_adv_rate(klass); return is_class_skill?(klass) ? 3 : is_slow_skill?() ? 1 : 2; end
	def is_class_skill?(klass); return @rules['reference']['class_skills'][klass].include?(@group); end
	def is_slow_skill?(); return @rules['reference']['slow_skills'].include?(@group); end
end

class SingleKlassProgress
  attr_reader :name, :level, :skill_list, :rules, :abilities
	def initialize(klass_data, rules)
		@name = klass_data['class']
		@level = klass_data['level'].to_i
		@skill_list = klass_data['skills']
		@rules = rules
		@abilities = Abilities.new(@rules, @level, ability_list)
	end

	def self.force_values(name, level, skill_list, rules)
		return SingleKlassProgress.new({"level" => level, "class" => name, "skills" => skill_list, "rules" => rules})
	end

	def mana_max; @rules["class_advancement"][@name]["mana"].to_i * @level; end

	#def inc_ranks(skill)
		#base_value = @skill_list.include?(skill.name.to_s) ? Skills.skill_ranks(@rules, @name, skill, @level) : 0
		#return abilities.adjust([skill, :ranks], base_value)
	#end

	#def add_modifier(key, value); @modifiers[key] = value if @modifiers[key] == nil or value > @modifiers[key]; end

	#def save_ranks(attr); return abilities.adjust([:save, attr, :ranks], Skills.skill_ranks(@rules, @name, attr, @level)); end
	#def skill_ranks(skill)
		#base_value = @skill_list.include?(skill.to_s) ? Skills.skill_ranks(@rules, @name, skill, @level) : 0
		#return abilities.adjust([skill, :ranks], base_value)
	#end

	#def bab_ranks; Skills.bab_ranks(@rules, @name, @level); end

	#def save_bonus(attr); return abilities.adjust([:save, attr, :bonus],0); end
	#def skill_bonus(skill); return abilities.adjust([skill, :bonus],0); end
	#def bab_bonus; return 0; end
end

module KlassProgress
  attr_reader :klass_list

	def initialize(character)
		super(character) rescue ArgumentError if defined?(super)
		@klass_list = character["classes"].map { |klass_data| SingleKlassProgress.new(klass_data, @rules) }
	end

	def level(); @klass_list.sum(&:level); end
	def save_total(attr); return save_ranks(attr) + half_mod(attr); end
	def save_ranks(attr); return @klass_list.sum { |progress| progress.save_ranks(attr) }; end
	def save_dice(attr); Skills.dice(@rules, save_total(attr)); end
	def save_bonus(attr); Skills.bonus(@rules, save_total(attr)); end
  
	def skill_list(); return @klass_list.map { |progress| progress.skill_list }.flatten; end
	def skill_total(skill); return skill_ranks(skill) + half_mod(Skills.skill_attr(@rules, skill).to_sym); end
	def skill_ranks(skill); return @klass_list.sum { |progress| progress.skill_ranks(skill) }; end
	#def skill_dice(skill); parse_formula(@rules["advancement"]["competency"]["skill_dice"], {"ranks" => skill_total(skill)}); end
	def skill_dice(skill); Skills.dice(@rules, skill_total(skill)); end
	def skill_bonus(skill); Skills.bonus(@rules, skill_total(skill)) + @klass_list.sum { |progress| progress.skill_bonus(skill) }; end

	def bab_total; return bab + half_mod(:dex); end
	def bab; return @klass_list.sum { |progress| progress.bab_ranks }; end
	def bab_dice; Skills.dice(@rules, bab_total); end
	def bab_bonus; Skills.bonus(@rules, bab_total); end

	def attack_dice(weapon_bonus); parse_formula(@rules["advancement"]["competency"]["skill_dice"], {"ranks" => bab_total}); end
	def attack_bonus(weapon_bonus); parse_formula(@rules["advancement"]["competency"]["skill_bonus"], {"ranks" => bab_total}) + weapon_bonus; end

	def full_klass(); @data["classes"].map { |klass| "#{klass["class"]} #{klass["level"]}" }.join(', '); end
	def mana_max; return @klass_list.sum { |progress| progress.mana_max(@rules) } + (defined?(super) ? super : 0); end

	def speed_modifiers; return @klass_list.sum { |progress| progress.speed_modifiers(@rules) } + (defined?(super) ? super : 0); end
	def ability_list; return @klass_list.map { |progress| progress.ability_list(@rules) }.flatten; end

	def damage_reduction(); return @klass_list.sum { |progress| progress.damage_reduction(@rules) } + (defined?(super) ? super : 0); end
	def damage_resiliance(); return @klass_list.sum { |progress| progress.damage_resiliance(@rules) } + (defined?(super) ? super : 0); end
end

module BaseStatsMath
	def ability_score_names
		return {"Strength" => :str, "Dexterity" => :dex, "Constitution" => :con, "Intelligence" => :int, "Wisdom" => :wis, "Charisma"=> :cha }
	end

	def str; return @data["ability_scores"]["str"].to_i; end
	def dex; return @data["ability_scores"]["dex"].to_i; end
	def con; return @data["ability_scores"]["con"].to_i; end
	def int; return @data["ability_scores"]["int"].to_i; end
	def wis; return @data["ability_scores"]["wis"].to_i; end
	def cha; return @data["ability_scores"]["cha"].to_i; end
	def initiative; return half_mod(:wis); end
	def score(attr); self.send(attr); end
	def half_mod(attr); (self.send(attr) / 2).to_i; end
	def attr_dice(attr); parse_formula(@rules["advancement"]["competency"]["attribute_dice"], {"attr" => attr}); end
	def attr_bonus(attr); parse_formula(@rules["advancement"]["competency"]["attribute_bonus"], {"attr" => attr}); end

	def hp_max; return parse_formula(@rules["advancement"]["natural"]["hp"][tier]); end
	def mana_max; return parse_formula(@rules["advancement"]["natural"]["mana"][tier]) + (defined?(super) ? super : 0); end
	def mana_regen; return (mana_max / 4).to_i; end
end

module TierMath
	def tier; @rules["advancement"]["tier"].find_index { |threshold| level < threshold } || @rules["advancement"]["tier"].length; end
	def tier_damage_reduction(attacker_tier); r = @rules["tier"]["damage_reduction"]; [0, r[tier] - r[attacker_tier]].min; end
	def damage_reduction(); return 0; end
	def damage_resiliance(); return @rules["tier"]["damage_resiliance"][tier] + (defined?(super) ? super : 0); end
	def combat_pool
		pool_math = rules["advancement"]["competency"]["combat_pool"][tier]
		combat_pool = pool_math["base"] + (pool_math["inc"] * level)
		combat_pool = pool_math["max"] if combat_pool > pool_math["max"]
		combat_pool + half_mod(:dex)
	end
end

module CharacterEquipment
  attr_reader :item_list, :all_items
	def initialize(character); super(character) if defined?(super); @all_items = Tools.load_json('items.json'); refresh_items; end
	def refresh_items; @item_list = @all_items.select { |item| item["owner_id"].to_i == @id }; end
	def equip_search(params = {}); return @item_list.select { |item| params.map { |key, value| item[key] == value }.all? }; end

	def weapon_list; return @item_list.select { |item| item["type"] == "weapon" }; end
	def shield_list; return @item_list.select { |item| item["type"] == "shield" }; end
	def equipped_list; return @item_list.select { |item| item["equipped"] == true }; end
	def ammunition; return @item_list.select { |item| item["properties"]["ammunition"] == true }; end
	def consumable; return @item_list.select { |item| item["properties"]["consumable"] == true }; end

	def weapon_dice(weapon_data); attack_dice(weapon_data["bonus"]); end
	def weapon_attack_bonus(weapon_data); attack_bonus(weapon_data["bonus"]); end

	def damage_reduction()
		armor = find_item("armor"); 
		dr = armor ? {"light" => 1, "medium" => 3, "heavy" => 6}[armor["subtype"]].to_i + armor["bonus"].to_i : 0
		return dr + (defined?(super) ? super : 0)
	end

	def damage_resiliance()
		armor = find_item("armor"); 
		dr = armor ? {"light" => 1, "medium" => 2, "heavy" => 3}[armor["subtype"]].to_i * armor["bonus"].to_i : 0
		return dr + (defined?(super) ? super : 0)
	end

	private
	def find_item(type); return @item_list.find { |item| item["type"] == type }; end  #Needs to add for armor
end

class CharacterSheet
  include TierMath
	include KlassProgress
  include BaseStatsMath
  include CharacterEquipment
  attr_reader :rules, :id, :data

  def initialize(character)
		@rules = Tools.load_json('rules.json')
		@id = character["id"]
		@data = character
		super(character)
	end

	def name; @data["name"]; end
	def player; @data["player"]; end
	def deity; @data["deity"]; end
	def race; @data["race"].reverse.join(' ').capitalize; end
	def race_sym; return (@data["race"][0] || @data["race"]).to_sym; end
	def speed; return 30 + @rules["reference"]["speed_modifiers"]["race"][race_sym.to_s].to_i + speed_modifiers; end

	def speed_modifiers; return 0 + super; end
	def mana_max; return 0 + super; end
	def damage_reduction(); return 0 + super; end  
	def damage_resiliance(); return 0 + super; end

	def add_plus(func, params = nil); r = params ? send(func, params) : send(func); return "#{'+' if r >= 0}#{r}"; end

	private

	def parse_formula(formula, params = {})
		result = formula.dup
		func_hash = params.dup.merge({str: :str, dex: :dex, con: :con, int: :int, wis: :wis, cha: :cha})

		func_hash.each do |key, func_sym|
			if func_sym.is_a?(Symbol)
				result.gsub!(key.to_s, send(func_sym).to_s)
			elsif func_sym.is_a?(Integer)
				result.gsub!(key.to_s, func_sym.to_s)
			end
		end
		
		eval(result)
	end
end
