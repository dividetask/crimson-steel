require_relative 'tools'

#module TierMath
	#def tier
		#@rules["advancement"]["tier"].each_with_index do |threshold, tier|
			#return tier if level < threshold
		#end
		
		#@rules["advancement"]["tier"].length
	#end
	#def tier_damage_reduction(); @rules["tier"]["damage_reduction"][tier]; end
	#def tier_damage_resiliance(); @rules["tier"]["damage_resiliance"][tier]; end
#end

#module SkillMath
	#def combat_pool
		#pool_math = rules["advancement"]["competency"]["combat_pool"][tier]
		#combat_pool = pool_math["base"] + (pool_math["inc"] * level)
		#combat_pool = pool_math["max"] if combat_pool > pool_math["max"]
		#combat_pool
	#end
#end

#module KlassMath
	#def level(); @data["classes"].map { |klass| klass["level"].to_i }.sum; end
	#def full_klass(); @data["classes"].map { |klass| "#{klass["class"]} #{klass["level"]}" }.join(', '); end

	#def bab
		#bab_increases = @data["classes"].map do |klass|
			#bab_adv_rate = @rules["class_advancement"][klass["class"]]["bab"]
			#bab_mod = @rules["advancement"]["competency"]["bab_ranks_per_level"][bab_adv_rate - 1]
			#(klass["level"].to_f * bab_mod[0].to_f / bab_mod[1].to_f).to_i
		#end
		#bab_increases.sum
	#end

	#def mana_from_klasses; @data["classes"].map { |klass| klass["mana"].to_i }.sum; end

	#private
	#def competency; return @rules["advancement"]["competency"]; end
	#def klass_rules(klass_name); return @rules["class_advancement"][klass_name]; end
#
	#def bab_klass_priority(klass_name); return klass_rules(klass_name)["bab"]; end
	#def bab_per_level(klass_name); frac = competency["bab_ranks_per_level"][bab_klass_priority(klass_name)]; return frac[0].to_f / frac[1].to_f; end

	#def bab_from_klass(klass_index)
		#klass_data = @data["classes"][klass_index]
		#return (klass_data["level"].to_i * bab_per_level(klass_data["class"])).to_i
	#end
#end

#module BaseStatsMath
	#def hp_max; return parse_formula(@rules["advancement"]["natural"]["hp"][tier]); end
	#def mana_max; return parse_formula(@rules["advancement"]["natural"]["mana"][tier]) + mana_from_klasses; end
	#def mana_regen; return (mana_max / 4).to_i; end

	#private

	#def parse_formula(formula)
		#stat_sym_list = [:str, :dex, :con, :int, :wis, :cha]
		#i = 0
		#formula_parts = []
		#while (i < formula.length)
			#if ( (i + 3 <= formula.length) and (stat_sym_list.include?(formula[i..(i+3)])) )
				#formula_parts << self.send(formula[i..(i+3)].to_sym).to_i
				#i = i + 3
			#end

			#if ["+", "-", "*", "/"].include? formula[i]
				#formula_parts << self.send(formula[i].to_sym)
				#i = i + 1
			#end

			#j = i
			#while ("0".."9").to_a.include(formula[j]) {j++}

			#if j > i
				#formula_parts << formula[i..j].to_i
				#i = j
			#end
		#end

		#i = 1
		#results = formula_parts[0]

		#while (i + 1 < formula_parts.length)
			#if formula_parts[i] == '+'
				#results = results + formula_parts[i+1]
				#i = i + 1
			#elsif formula_parts[i] == '-'
				#results = results - formula_parts[i+1]
				#i = i + 1
			#elsif formula_parts[i] == '*'
				#results = results * formula_parts[i+1]
				#i = i + 1
			#elsif formula_parts[i] == '/'
				#results = results / formula_parts[i+1]
				#i = i + 1
			#end
		#end
		#results
		#0
	#end
#end

class CharacterSheet
  #include TierMath
  #include KlassMath
  #include BaseStatsMath
  #include SkillMath
  attr_reader :rules, :id, :data

  def initialize(character); @rules = Tools.load_json('rules.json'); @id = character["id"]; @data = character; end
	def name; @data["name"]; end
	def player; @data["player"]; end
	def deity; @data["deity"]; end
	def race; @data["race"].reverse.join(' ').capitalize; end
	#def damage_reduction(); tier_damage_reduction; end  #Needs to add for armor
	#def damage_resiliance(); tier_damage_resiliance; end  #Needs to add for armor
end

