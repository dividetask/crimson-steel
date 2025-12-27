require_relative 'tools'

class SingleKlassProgress
  attr_reader :name, :level, :skill_list
	def initialize(klass_data); @name = klass_data['class']; @level = klass_data['level'].to_i; @skill_list = klass_data['skills']; end
	def self.force_values(name, level, skill_list); return SingleKlassProgress.new({"level" => level, "class" => name, "skills" => skill_list}); end

	def save_ranks(attr, rules)
		return ranks(rules["class_advancement"][@name]["saves"][attr.to_s], rules["advancement"]["competency"]["save_ranks_per_level"])
	end

	def is_class_skill(skill, rules); return rules["reference"]["class_skills"][@name.to_s].include?(skill.to_s); end
	def skill_ranks(skill, rules)
		return 0 unless @skill_list.include?(skill)
		return ranks(skill_adv_rate(skill,rules), rules["advancement"]["competency"]["skill_ranks_per_level"])
	end

	private
	def skill_adv_rate(skill, rules); return is_class_skill(skill, rules) ? 3 : 1; end
	def ranks(adv_rate, adv_rules); mod = adv_rules[adv_rate - 1]; return (@level.to_f * mod[0].to_f / mod[1].to_f).to_i; end
end

module KlassProgress
  attr_reader :klass_list

	def initialize(character); @klass_list = character["classes"].map { |klass_data| SingleKlassProgress.new(klass_data) }; end
	def level(); @klass_list.sum(&:level); end
	def save_total(attr); return save_ranks(attr) + half_mod(attr); end
	def save_ranks(attr); return @klass_list.sum { |progress| progress.save_ranks(attr, @rules) }; end
	def save_dice(attr); parse_formula(@rules["advancement"]["competency"]["save_dice"], {"ranks" => save_total(attr)}); end
	def save_bonus(attr); parse_formula(@rules["advancement"]["competency"]["save_bonus"], {"ranks" => save_total(attr)}); end

	def skill_ranks(skill); return @klass_list.sum { |progress| progress.skill_ranks(skill, @rules) }; end
	def skill_list(); return @klass_list.map { |progress| progress.skill_list }.flatten; end
	#def skill_dice(skill); parse_formula(@rules["advancement"]["competency"]["skill_dice"], {"ranks" => skill_ranks(skill)}); end
	#def skill_bonus(skill); parse_formula(@rules["advancement"]["competency"]["skill_bonus"], {"ranks" => skill_ranks(skill)}); end
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
	def score(attr); self.send(attr); end
	def half_mod(attr); (self.send(attr) / 2).to_i; end
	def attr_dice(attr); parse_formula(@rules["advancement"]["competency"]["attribute_dice"], {"attr" => attr}); end
	def attr_bonus(attr); parse_formula(@rules["advancement"]["competency"]["attribute_bonus"], {"attr" => attr}); end

	def hp_max; return parse_formula(@rules["advancement"]["natural"]["hp"][tier]); end
	def mana_max; return parse_formula(@rules["advancement"]["natural"]["mana"][tier]) + mana_from_klasses; end
	def mana_regen; return (mana_max / 4).to_i; end
end

module TierMath
	def tier
		@rules["advancement"]["tier"].each_with_index do |threshold, tier|
			return tier if level < threshold
		end
		
		@rules["advancement"]["tier"].length
	end
	def tier_damage_reduction(); @rules["tier"]["damage_reduction"][tier]; end
	def tier_damage_resiliance(); @rules["tier"]["damage_resiliance"][tier]; end
end

module KlassMath
	def full_klass(); @data["classes"].map { |klass| "#{klass["class"]} #{klass["level"]}" }.join(', '); end

	def bab
		bab_increases = @data["classes"].map do |klass|
			bab_adv_rate = @rules["class_advancement"][klass["class"]]["bab"]
			bab_mod = @rules["advancement"]["competency"]["bab_ranks_per_level"][bab_adv_rate - 1]
			(klass["level"].to_f * bab_mod[0].to_f / bab_mod[1].to_f).to_i
		end
		bab_increases.sum
	end

	def mana_from_klasses; @data["classes"].map { |klass| @rules["class_advancement"][klass["class"]]["mana"].to_i * klass["level"]}.sum; end

	private
	def competency; return @rules["advancement"]["competency"]; end
	def klass_rules(klass_name); return @rules["class_advancement"][klass_name]; end

	def bab_klass_priority(klass_name); return klass_rules(klass_name)["bab"]; end
	def bab_per_level(klass_name); frac = competency["bab_ranks_per_level"][bab_klass_priority(klass_name)]; return frac[0].to_f / frac[1].to_f; end

	def bab_from_klass(klass_index)
		klass_data = @data["classes"][klass_index]
		return (klass_data["level"].to_i * bab_per_level(klass_data["class"])).to_i
	end
end

class CharacterSheet
  include TierMath
	include KlassProgress
  include KlassMath
  include BaseStatsMath
  include SkillMath
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
	def damage_reduction(); tier_damage_reduction; end  #Needs to add for armor
	def damage_resiliance(); tier_damage_resiliance; end  #Needs to add for armor
	def add_plus(func, params = nil); r = send(func,params); return "#{'+' if r >= 0}#{r}"; end

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

