require_relative 'tools'

module SkillMath
	def combat_pool
		pool_math = rules["advancement"]["competency"]["combat_pool"][tier]
		combat_pool = pool_math["base"] + (pool_math["inc"] * level)
		combat_pool = pool_math["max"] if combat_pool > pool_math["max"]
		combat_pool + half_mod(:dex)
	end
end

module BaseStatsMath
	def str; return @data["ability_scores"]["str"]; end
	def dex; return @data["ability_scores"]["dex"]; end
	def con; return @data["ability_scores"]["con"]; end
	def int; return @data["ability_scores"]["int"]; end
	def wis; return @data["ability_scores"]["wis"]; end
	def cha; return @data["ability_scores"]["cha"]; end
	def half_mod(attr); (self.send(attr) / 2).to_i; end

	def hp_max; return parse_formula(@rules["advancement"]["natural"]["hp"][tier]); end
	def mana_max; return parse_formula(@rules["advancement"]["natural"]["mana"][tier]) + mana_from_klasses; end
	def mana_regen; return (mana_max / 4).to_i; end

	private

	def parse_formula(formula)
		result = formula.dup
		func_list = [:str, :dex, :con, :int, :wis, :cha]
		
		func_list.each do |func_sym|
			result.gsub!(func_sym.to_s, send(func_sym).to_s)
		end
		
		eval(result)
	end
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
	def level(); @data["classes"].map { |klass| klass["level"].to_i }.sum; end
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
  include KlassMath
  include BaseStatsMath
  include SkillMath
  attr_reader :rules, :id, :data

  def initialize(character); @rules = Tools.load_json('rules.json'); @id = character["id"]; @data = character; end
	def name; @data["name"]; end
	def player; @data["player"]; end
	def deity; @data["deity"]; end
	def race; @data["race"].reverse.join(' ').capitalize; end
	def damage_reduction(); tier_damage_reduction; end  #Needs to add for armor
	def damage_resiliance(); tier_damage_resiliance; end  #Needs to add for armor
end

