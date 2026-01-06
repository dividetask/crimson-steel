require_relative 'tools'

class Compendium
  attr_reader :data

  def initialize; @data = Tools.load_json('compendium.json'); end
	def format_name(ability_name); return ability_name.gsub('_', ' ').split(' ').map(&:capitalize).join(' '); end
	def ability(entry); return @data["abilities"][entry.to_s]; end
end

module Skills
	def self.skill_group(skill, rules); return skill_list(rules).find { |skill_group, attr| skills_match?(skill_group, skill) }[0]; end
	def self.skill_attr(skill, rules); return skill_list(rules)[skill_group(skill, rules)].to_sym; end
	def self.skill_list(rules); rules["reference"]["skill_list"]; end
	def self.skills_match?(skill_g, skill); skill_g == skill.to_s || (skill_g.end_with?('_') && skill.to_s.start_with?(skill_g)); end
end

class SingleKlassProgress
  attr_reader :name, :level, :skill_list
	def initialize(klass_data); @name = klass_data['class']; @level = klass_data['level'].to_i; @skill_list = klass_data['skills']; end
	def self.force_values(name, level, skill_list); return SingleKlassProgress.new({"level" => level, "class" => name, "skills" => skill_list}); end

	def save_ranks(attr, rules)
		return ranks(rules["class_advancement"][@name]["saves"][attr.to_s], rules["advancement"]["competency"]["save_ranks_per_level"])
	end

	def is_class_skill(skill, rules); return rules['reference']['class_skills'][@name].include?(Skills.skill_group(skill, rules)); end
	def skill_ranks(skill, rules)
		return 0 unless @skill_list.include?(skill.to_s)
		return ranks(skill_adv_rate(skill,rules), rules["advancement"]["competency"]["skill_ranks_per_level"])
	end

	def bab(rules); return ranks(rules["class_advancement"][@name]["bab"], rules["advancement"]["competency"]["skill_ranks_per_level"]); end

	def mana_max(rules); rules["class_advancement"][@name]["mana"].to_i * @level; end
	def speed_modifiers(rules); (speed_rules(rules)["class"][@name] || []).sum { |level, bonus| @level >= level.to_i ? bonus.to_i : 0}; end
	def ability_list(rules); return rules["reference"]["class_abilities"][@name].select { |level, list| @level >= level.to_i }.values.flatten; end

	def damage_reduction(rules); return ability_list(rules).sum { |ability| calc_ability_bonus(rules, ability, "damage_reduction") }; end
	def damage_resiliance(rules); return ability_list(rules).sum { |ability| calc_ability_bonus(rules, ability, "damage_resiliance") }; end
	def skill_bonus(skill, rules); return ability_list(rules).sum { |ability| calc_ability_bonus(rules, ability, skill) }; end
	def save_bonus(attr, rules); return ability_list(rules).sum { |ability| calc_ability_bonus(rules, ability, attr) }; end

	private
	def calc_ability_bonus(rules, ability, var); calc_active_bonus(rules, ability, var) + calc_passive_bonus(rules, ability, var); end
	def calc_active_bonus(rules, ability, var); parse_formula(traverse_hash(rules["reference"]["abilities"], [ability, "active", var])); end
	def calc_passive_bonus(rules, ability, var); parse_formula(traverse_hash(rules["reference"]["abilities"], [ability, "passive", var])); end

	def traverse_hash(hash, key_list)
		return hash if key_list.empty?
		return 0 unless hash[key_list[0]]
		return traverse_hash(hash[key_list[0]], key_list[1..-1])
	end

	def skill_adv_rate(skill, rules); return is_class_skill(skill, rules) ? 3 : 2; end
	def ranks(adv_rate, adv_rules); mod = adv_rules[adv_rate - 1]; return (@level.to_f * mod[0].to_f / mod[1].to_f).to_i; end
	def speed_rules(rules); return rules["reference"]["speed_modifiers"]; end

	def parse_formula(formula)
		return 0 if formula == 0 or formula == nil
		result = formula.dup

		{level: :level}.each do |key, func_sym|
			if func_sym.is_a?(Symbol)
				result.gsub!(key.to_s, send(func_sym).to_s)
			elsif func_sym.is_a?(Integer)
				result.gsub!(key.to_s, func_sym.to_s)
			end
		end
		
		eval(result)
	end
end

module KlassProgress
  attr_reader :klass_list

	def initialize(character)
		@klass_list = character["classes"].map { |klass_data| SingleKlassProgress.new(klass_data) }
		super(character); rescue ArgumentError
	end

	def level(); @klass_list.sum(&:level); end
	def save_total(attr); return save_ranks(attr) + half_mod(attr); end
	def save_ranks(attr); return @klass_list.sum { |progress| progress.save_ranks(attr, @rules) }; end
	def save_dice(attr); parse_formula(@rules["advancement"]["competency"]["save_dice"], {"ranks" => save_total(attr)}); end
	def save_bonus(attr)
		base = parse_formula(@rules["advancement"]["competency"]["save_bonus"], {"ranks" => save_total(attr)})
		class_bonus = @klass_list.sum { |progress| progress.save_bonus(attr, @rules) }
		return base + class_bonus
	 end

	def clean_skill_name(skill); return skill.gsub('_', ' ').split(' ').map(&:capitalize).join(' '); end
  
	def get_skill_attr(skill); return @rules["reference"]["skill_list"][Skills.skill_group(skill, rules)].to_sym; end
	def skill_total(skill); attr = get_skill_attr(skill).to_sym; return skill_ranks(skill) + half_mod(attr); end
	def skill_ranks(skill); return @klass_list.sum { |progress| progress.skill_ranks(skill, @rules) }; end
	def skill_list(); return @klass_list.map { |progress| progress.skill_list }.flatten; end
	def skill_dice(skill); parse_formula(@rules["advancement"]["competency"]["skill_dice"], {"ranks" => skill_total(skill)}); end
	def skill_bonus(skill)
		base = parse_formula(@rules["advancement"]["competency"]["skill_bonus"], {"ranks" => skill_total(skill)})
		class_bonus = @klass_list.sum { |progress| progress.skill_bonus(skill, @rules) }
		return base + class_bonus
	 end

	def bab; return @klass_list.sum { |progress| progress.bab(@rules) }; end
	def bab_total; return bab + half_mod(:dex); end
	def bab_dice; parse_formula(@rules["advancement"]["competency"]["skill_dice"], {"ranks" => bab_total}); end
	def bab_bonus; parse_formula(@rules["advancement"]["competency"]["skill_bonus"], {"ranks" => bab_total}); end

	def attack_dice(weapon_bonus); parse_formula(@rules["advancement"]["competency"]["skill_dice"], {"ranks" => bab_total}); end
	def attack_bonus(weapon_bonus); parse_formula(@rules["advancement"]["competency"]["skill_bonus"], {"ranks" => bab_total}) + weapon_bonus; end

	def full_klass(); @data["classes"].map { |klass| "#{klass["class"]} #{klass["level"]}" }.join(', '); end
	def mana_max; return @klass_list.sum { |progress| progress.mana_max(@rules) } + (defined?(super) ? super : 0); end

	def speed_modifiers; return @klass_list.sum { |progress| progress.speed_modifiers(@rules) } + (defined?(super) ? super : 0); end
	def ability_list; return @klass_list.map { |progress| progress.ability_list(@rules) }.flatten; end

	def damage_reduction(); return @klass_list.sum { |progress| progress.damage_reduction(@rules) } + (defined?(super) ? super : 0); end
	def damage_resiliance(); return @klass_list.sum { |progress| progress.damage_resiliance(@rules) } + (defined?(super) ? super : 0); end
end

module SkillMath
	def combat_pool
		pool_math = rules["advancement"]["competency"]["combat_pool"][tier]
		combat_pool = pool_math["base"] + (pool_math["inc"] * level)
		combat_pool = pool_math["max"] if combat_pool > pool_math["max"]
		combat_pool + half_mod(:dex)
	end
	#def skill_dice(skill); parse_formula(@rules["advancement"]["competency"]["attribute_dice"], {"attr" => attr}); end
			#"skill_dice": "6+((skill/2)%5)",

	#def skills
		#return [ {name: "Heal", ranks: 6, dice: 6, bonus: 2}, {name: "Sense Motive", ranks: 6, dice: 6, bonus: 2} ]
	#end
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
	#def mana_max; return parse_formula(@rules["advancement"]["natural"]["mana"][tier]) + mana_from_klasses; end
	def mana_max; return parse_formula(@rules["advancement"]["natural"]["mana"][tier]) + (defined?(super) ? super : 0); end
	def mana_regen; return (mana_max / 4).to_i; end
end

module TierMath
	def tier; @rules["advancement"]["tier"].find_index { |threshold| level < threshold } || @rules["advancement"]["tier"].length; end
	def tier_damage_reduction(attacker_tier); r = @rules["tier"]["damage_reduction"]; [0, r[tier] - r[attacker_tier]].min; end
	def damage_reduction(); return 0; end
	def damage_resiliance(); return @rules["tier"]["damage_resiliance"][tier] + (defined?(super) ? super : 0); end
end

module CharacterEquipment
  attr_reader :item_list, :all_items
	def initialize(character); super(character) if defined?(super); @all_items = Tools.load_json('items.json'); refresh_items; end
	def refresh_items; @item_list = @all_items.select { |item| item["owner_id"].to_i == @id }; end
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
  include SkillMath
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
