require_relative '../helpers'
require 'json'

module SpecData
  attr_reader :index, :expected
	def self.clean(hash_or_array)
		return hash_or_array if hash_or_array.is_a?(Hash)
		return hash_or_array.map.with_index { |data, index| [index, data] }.to_h
	end

end


RSpec.describe CharacterSheet do
	let(:rules) { JSON.parse(File.read('spec/fixtures/rules.json')) }
	let(:character_list) { JSON.parse(File.read('spec/fixtures/characters.json')) }

	describe '#CharacterSheet' do
		context 'Lookup static details' do
			it 'finds name, and player info' do
				SpecData.clean([['Joe', 'Blow'], ['Kevin', 'Quan'], ['Bob', 'Bobby'], ['Paul', 'Pauly']]).each do |index, expected|
					character = CharacterSheet.new(character_list[index])
					expect(character.name).to eq(expected[0])
					expect(character.player).to eq(expected[1])
				end
			end

			it 'finds deity' do
				{0 => 'Gorum', 2 => 'Calistria'}.each do |index, expected|
					character = CharacterSheet.new(character_list[index])
					expect(character.deity).to eq(expected)
				end
			end

			it 'gracefully handles null dieties' do
				[1, 3].each do |index|
					character = CharacterSheet.new(character_list[index])
					expect(character.deity).to eq(nil)
				end
			end

			it 'correctly displays race' do
				SpecData.clean(['Hill dwarf', 'Human', 'High elf', 'Human']).each do |index, expected_race|
					character = CharacterSheet.new(character_list[index])
					expect(character.race).to eq(expected_race)
				end
			end
		end
	end

	describe '#KlassMath' do
		context 'Verify level math' do
			it 'calculates level for single class characters' do
				{0 => 1, 1 => 8}.each do |index, expected|
					character = CharacterSheet.new(character_list[index])
					expect(character.level).to eq(expected)
				end
			end

			it 'calculates level for multi class characters' do
				{2 => 7, 3 => 4}.each do |index, expected|
					character = CharacterSheet.new(character_list[index])
					expect(character.level).to eq(expected)
				end
			end
		end
	end

	describe '#TierMath' do
		context 'Verify class mana math' do
			it 'calculates tier with example characters' do
				SpecData.clean([4, 8, 19, 10]).each do |index, expected|
					character = CharacterSheet.new(character_list[index])
					expect(character.mana_from_klasses).to eq(expected)
				end
			end
		end

		context 'Verify tier math' do
			it 'calculates tier with example characters' do
				tier = 0
				expected_hash = (0..rules['advancement']['tier'].max).to_a.map do |level|
					while (rules['advancement']['tier'][tier]) && (level >= rules['advancement']['tier'][tier])
						tier += 1
					end
					tier
				end

				character_list.each do |character_data|
					character = CharacterSheet.new(character_data)
					expect(character.tier).to eq(expected_hash[character.level])
				end
			end

			it 'calculates tier for each level' do
				tier = 0
				expected_hash = (0..rules['advancement']['tier'].max).to_a.map do |level|
					while (rules['advancement']['tier'][tier]) && (level >= rules['advancement']['tier'][tier])
						tier += 1
					end
					tier
				end

				(0..rules['advancement']['tier'].max).to_a.each do |level|
					character = CharacterSheet.new(character_list.sample)
					allow(character).to receive(:level).and_return(level)

					expect(character.tier).to eq(expected_hash[level])
				end
			end

			it 'calculates tier damage reduction with example characters' do
				character_list.each do |character_data|
					character = CharacterSheet.new(character_data)
					expect(character.tier_damage_reduction).to eq(rules['tier']['damage_reduction'][character.tier])
				end
			end

			it 'calculates tier damage resiliance with example characters' do
				character_list.each do |character_data|
					character = CharacterSheet.new(character_data)
					expect(character.tier_damage_resiliance).to eq(rules['tier']['damage_resiliance'][character.tier])
				end
			end

			it 'calculates tier damage reduction for each level' do
				(0..rules['advancement']['tier'].max).to_a.each do |level|
					character = CharacterSheet.new(character_list.sample)
					allow(character).to receive(:level).and_return(level)
					expect(character.tier_damage_reduction).to eq(rules['tier']['damage_reduction'][character.tier])
				end
			end

			it 'calculates tier damage resiliance for each level' do
				(0..rules['advancement']['tier'].max).to_a.each do |level|
					character = CharacterSheet.new(character_list.sample)
					allow(character).to receive(:level).and_return(level)
					expect(character.tier_damage_resiliance).to eq(rules['tier']['damage_resiliance'][character.tier])
				end
			end
		end
	end

	describe '#BaseStatsMath' do
		context 'Attr lookup' do
			it 'looks up attr with example characters' do
				[{"str": 10, "dex": 11, "con": 12, "int": 13, "wis": 14, "cha": 15},
					{"str": 21, "dex": 22, "con": 23, "int": 24, "wis": 25, "cha": 26},
					{"str": 4, "dex": 7, "con": 5, "int": 6, "wis": 1, "cha": 3},
					{"str": 2, "dex": 5, "con": 9, "int": 2, "wis": 8, "cha": 1}].each_with_index do |expected_hash, index|
					character = CharacterSheet.new(character_list[index])
					expected_hash.each do |key, expected|
						expect(character.send(key)).to eq(expected)
					end
				end
			end

			it 'calcs half mod with example characters' do
				SpecData.clean([{"str": 10, "dex": 11, "con": 12, "int": 13, "wis": 14, "cha": 15},
					{"str": 21, "dex": 22, "con": 23, "int": 24, "wis": 25, "cha": 26},
					{"str": 4, "dex": 7, "con": 5, "int": 6, "wis": 1, "cha": 3},
					{"str": 2, "dex": 5, "con": 9, "int": 2, "wis": 8, "cha": 1}]).each do |index, expected_hash|
					character = CharacterSheet.new(character_list[index])
					expected_hash.each do |key, expected|
						expect(character.half_mod(key)).to eq((expected / 2).to_i)
					end
				end
			end
		end

		context 'parse_formula' do
			it 'calculates max hp with example characters' do
				SpecData.clean([12, 23*3, 5*2, 9*2]).each do |index, expected|
					character = CharacterSheet.new(character_list[index])
					expect(character.hp_max).to eq(expected)
				end
			end

			it 'calculates max mana with example characters' do
				SpecData.clean([10, 56, 25, 12]).each do |index, expected|
					character = CharacterSheet.new(character_list[index])
					expect(character.mana_max).to eq(expected)
				end
			end

			it 'calculates attr_dice with example characters' do
				SpecData.clean([{"str": 4, "dex": 4, "con": 5, "int": 5, "wis": 6, "cha": 6},
					{"str": 4, "dex": 5, "con": 5, "int": 6, "wis": 6, "cha": 7},
					{"str": 6, "dex": 7, "con": 6, "int": 7, "wis": 4, "cha": 5},
					{"str": 5, "dex": 6, "con": 8, "int": 5, "wis": 8, "cha": 4}]).each do |index, expected_hash|
					character = CharacterSheet.new(character_list[index])
					expected_hash.each do |key, expected|
						expect(character.attr_dice(key)).to eq(expected)
					end
				end
			end


			it 'calculates attr_bonus with example characters' do
				SpecData.clean([{"str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0},
					{"str": 1, "dex": 1, "con": 1, "int": 1, "wis": 1, "cha": 1},
					{"str": -1, "dex": -1, "con": -1, "int": -1, "wis": -1, "cha": -1},
					{"str": -1, "dex": -1, "con": -1, "int": -1, "wis": -1, "cha": -1}]).each do |index, expected_hash|
					character = CharacterSheet.new(character_list[index])
					expected_hash.each do |key, expected|
						expect(character.attr_bonus(key)).to eq(expected)
					end
				end
			end

			it 'calculates attr_bonus for each attr from 0 to 40' do
				(0..40).to_a.each do |score|
					sym = [:str, :dex, :con, :int, :wis, :cha].sample
					character = CharacterSheet.new(character_list.sample)
					allow(character).to receive(sym).and_return(score)
					expect(character.attr_bonus(sym)).to eq( (score / 10).to_i - 1)
				end
			end

			it 'calculates save ranks for single classes correctly' do
				(0..20).to_a.each do |level|
					{
						"cleric": [:wis, :cha], "barbarian": [:str, :con] , "rogue": [:dex, :int] ,
						"druid": [:int, :wis], "wizard": [:int, :wis], "ranger": [:str, :dex],
						"arcane_trickster": [:dex, :int], "bard": [:dex, :cha]}.each do |klass_name, high_attr|
						[:str, :dex, :con, :int, :wis, :cha].each do |attr|
							character = CharacterSheet.new(character_list.sample)
							test_klass = SingleKlassProgress.force_values(klass_name.to_s, level, [])
							character.instance_variable_set(:@klass_list, [test_klass])

							if high_attr.include?(attr)
								expect(character.save_ranks(attr)).to eq(((5.0 * level) / 3).to_i)
							else
								expect(character.save_ranks(attr)).to eq(((2.0 * level) / 3).to_i)
							end
						end
					end
				end
			end

			it 'calculates skill ranks for single classes correctly' do
				(0..20).to_a.each do |level|
					fast = ((5.0 * level) / 3).to_i
					slow = ((3.0 * level) / 3).to_i

					{"cleric": {"healing": fast, "religion": fast, "acrobatics": slow, "stealth": slow},
					"barbarian": {"athletics": fast, "intimidate": fast, "planes": slow, "disguise": slow}}.each do |klass_name, skill_data|
						skill_data.each do |skill_name, expected|
							character = CharacterSheet.new(character_list.sample)
							test_klass = SingleKlassProgress.force_values(klass_name.to_s, level, [skill_name.to_s])
							character.instance_variable_set(:@klass_list, [test_klass])
							expect(character.skill_ranks(skill_name.to_sym)).to eq(expected)
						end
					end
				end
			end

			it 'calculates skill total for single classes correctly' do
				(0..20).to_a.each do |ranks|
					(0..20).to_a.each do |score|
						{"healing": :wis, "religion": :int, "acrobatics": :dex, "stealth": :dex, 
						"athletics": :str, "intimidate": :cha, "planes": :int, "disguise": :cha}.each do |skill_name, attr|
							character = CharacterSheet.new(character_list.sample)
							allow(character).to receive(attr).and_return(score)
							allow(character).to receive(:skill_ranks).and_return(ranks)
							expect(character.skill_total(skill_name.to_sym)).to eq((score / 2).to_i + ranks)
						end
					end
				end
			end

			it 'calculates get skill attr skill correctly' do
				{"healing": :wis, "religion": :int, "acrobatics": :dex, "stealth": :dex, 
				"athletics": :str, "intimidate": :cha, "planes": :int, "disguise": :cha}.each do |skill_name, attr|
					character = CharacterSheet.new(character_list.sample)
					expect(character.get_skill_attr(skill_name)).to eq(attr)
				end
			end

			it 'calculates get skill data correctly' do
				skill_data = {"healing" => 8, "religion" => 8, "acrobatics" => 5, "stealth" => 5}
				character = CharacterSheet.new(character_list.sample)
				test_klass = SingleKlassProgress.force_values('cleric', 5, skill_data.keys)
				character.instance_variable_set(:@klass_list, [test_klass])
				expect(character.skill_list).to eq(skill_data.keys)
				skill_data.each do |skill_name, expected|
					expect(character.skill_ranks(skill_name)).to eq(expected)
				end
			end

		end
	end

	describe '#SkillMath' do
		context 'Verify combat pool math' do
			it 'calculates combat pool with example characters' do
				[9, 26, 18, 12].each_with_index do |expected, index|
					character = CharacterSheet.new(character_list[index])
					expect(character.combat_pool).to eq(expected)
				end
			end
		end
	end
end
