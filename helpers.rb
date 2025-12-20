
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

module SkillMath
	def combat_pool
		pool_math = rules["advancement"]["competency"]["combat_pool"][tier]
		combat_pool = pool_math["base"] + (pool_math["inc"] * level)
		combat_pool = pool_math["max"] if combat_pool > pool_math["max"]
		combat_pool
	end
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

	def mana_from_klasses; @data["classes"].map { |klass| klass["mana"].to_i }.sum; end

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

module BaseStatsMath
	def hp_max; return parse_formula(@rules["advancement"]["natural"]["hp"][tier]); end
	def mana_max; return parse_formula(@rules["advancement"]["natural"]["mana"][tier]) + mana_from_klasses; end
	def mana_regen; return (mana_max / 4).to_i; end

	private

	def parse_formula(formula)
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
		0
	end
end

class CharacterSheet
  include TierMath
  include KlassMath
  include BaseStatsMath
  include SkillMath
  attr_reader :rules, :id, :data

  def initialize(character, rules); @rules = rules; @id = character["id"]; @data = character; end
	def name; @data["name"]; end
	def player; @data["player"]; end
	def deity; @data["deity"]; end
	def race; @data["race"].reverse.join(' '); end
	def damage_reduction(); tier_damage_reduction; end  #Needs to add for armor
	def damage_resiliance(); tier_damage_resiliance; end  #Needs to add for armor
end

module CharacterHelpers
  def load_json(filename)
    file_path = File.join(settings.root, 'data', filename)
    JSON.parse(File.read(file_path)) if File.exist?(file_path)
  end

  def get_info(character)
		rules = load_json('rules.json')
		sheet = CharacterSheet.new(character, rules)

		info = {name: sheet.name, player: sheet.player, deity: sheet.deity, race: sheet.race, level: sheet.level, tier: sheet.tier, bab: sheet.bab}
		info[:combat_pool] = sheet.combat_pool
		info[:damage_reduction] = sheet.damage_reduction
		info[:damage_resiliance] = sheet.damage_resiliance
		info[:hp_max] = "?"
		info[:mana_max] = "?"
		info[:mana_regen] = "?"
		info[:full_klass] = sheet.full_klass

		info[:ability_scores] = [
			{name: "Strength", 			score: character["ability_scores"]["str"]},
			{name: "Dexterity", 		score: character["ability_scores"]["dex"]},
			{name: "Constitution", 	score: character["ability_scores"]["con"]},
			{name: "Intelligence", 	score: character["ability_scores"]["int"]},
			{name: "Wisdom", 				score: character["ability_scores"]["wis"]},
			{name: "Charisma",		 	score: character["ability_scores"]["cha"]} ]

		info[:ability_scores].map! do |ability_details|
			ability_details[:half_score] = (ability_details[:score].to_i / 2)
			ability_details[:skill_dice] = 6
			ability_details[:skill_bonus] = "+0"
			ability_details[:save_dice] = 6
			ability_details[:save_bonus] = "+0"
			ability_details
		end

		info[:skills] = [ {name: "Heal", ranks: 6, dice: 6, bonus: 2}, {name: "Sense Motive", ranks: 6, dice: 6, bonus: 2} ]

		info
	end
end
