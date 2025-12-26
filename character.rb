require_relative 'tools'

module SkillMath
	def combat_pool
		pool_math = rules["advancement"]["competency"]["combat_pool"][tier]
		combat_pool = pool_math["base"] + (pool_math["inc"] * level)
		combat_pool = pool_math["max"] if combat_pool > pool_math["max"]
		combat_pool + half_mod(:dex)
	end
	#def skill_dice(skill); parse_formula(@rules["advancement"]["competency"]["attribute_dice"], {"attr" => attr}); end
			#"skill_dice": "6+((skill/2)%5)",

	def skills
		return [ {name: "Heal", ranks: 6, dice: 6, bonus: 2}, {name: "Sense Motive", ranks: 6, dice: 6, bonus: 2} ]
	end
end

module BaseStatsMath
	def cleaned_ability_scores
		return [
			{name: "Strength", 			sym: :str},
			{name: "Dexterity", 		sym: :dex},
			{name: "Constitution", 	sym: :con},
			{name: "Intelligence", 	sym: :int},
			{name: "Wisdom", 				sym: :wis},
			{name: "Charisma",		 	sym: :cha} ].map do |ability_details|
				ability_details[:score] = send(ability_details[:sym])
				ability_details[:half_score] = half_mod(ability_details[:sym])
				ability_details[:skill_dice] = 6
				ability_details[:skill_bonus] = "+0"
				ability_details[:save_dice] = 6
				ability_details[:save_bonus] = "+0"
				ability_details
		end
	end

	def str; return @data["ability_scores"]["str"].to_i; end
	def dex; return @data["ability_scores"]["dex"].to_i; end
	def con; return @data["ability_scores"]["con"].to_i; end
	def int; return @data["ability_scores"]["int"].to_i; end
	def wis; return @data["ability_scores"]["wis"].to_i; end
	def cha; return @data["ability_scores"]["cha"].to_i; end
	def half_mod(attr); (self.send(attr) / 2).to_i; end
	def attr_dice(attr); parse_formula(@rules["advancement"]["competency"]["attribute_dice"], {"attr" => attr}); end

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

	private

	def parse_formula(formula, params = {})
		result = formula.dup
		func_hash = params.dup.merge({str: :str, dex: :dex, con: :con, int: :int, wis: :wis, cha: :cha})

		func_hash.each do |key, func_sym|
			result.gsub!(key.to_s, send(func_sym).to_s)
		end

		#func_list = [:str, :dex, :con, :int, :wis, :cha]
		
		#func_list.each do |func_sym|
			#result.gsub!(func_sym.to_s, send(func_sym).to_s)
		#end
		
		eval(result)
	end
end

