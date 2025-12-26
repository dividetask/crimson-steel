require_relative '../helpers'
require 'json'

RSpec.describe CharacterSheet do
	let(:rules) { JSON.parse(File.read('spec/fixtures/rules.json')) }
	let(:character_list) { JSON.parse(File.read('spec/fixtures/characters.json')) }

	describe '#CharacterSheet' do
		context 'Lookup static details' do
			it 'finds name, and player info' do
				[['Joe', 'Blow'], ['Kevin', 'Quan'], ['Bob', 'Bobby'], ['Paul', 'Pauly']].each_with_index do |expected, index|
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
				['Hill dwarf', 'Human', 'High elf', 'Human'].each_with_index do |expected_race, index|
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
				[4, 8, 19, 10].each_with_index do |expected, index|
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
				[{"str": 10, "dex": 11, "con": 12, "int": 13, "wis": 14, "cha": 15},
					{"str": 21, "dex": 22, "con": 23, "int": 24, "wis": 25, "cha": 26},
					{"str": 4, "dex": 7, "con": 5, "int": 6, "wis": 1, "cha": 3},
					{"str": 2, "dex": 5, "con": 9, "int": 2, "wis": 8, "cha": 1}].each_with_index do |expected_hash, index|
					character = CharacterSheet.new(character_list[index])
					expected_hash.each do |key, expected|
						expect(character.half_mod(key)).to eq((expected / 2).to_i)
					end
				end
			end
		end

		context 'parse_formula' do
			it 'calculates max hp with example characters' do
				[12, 23*3, 5*2, 9*2].each_with_index do |expected, index|
					character = CharacterSheet.new(character_list[index])
					expect(character.hp_max).to eq(expected)
				end
			end

			it 'calculates max mana with example characters' do
				[10, 56, 25, 12].each_with_index do |expected, index|
					character = CharacterSheet.new(character_list[index])
					expect(character.hp_max).to eq(expected)
				end
			end
		end
	end

	describe '#SkillMath' do
		context 'Verify combat pool math' do
			it 'calculates combat pool with example characters' do
				[9, 26, 18, 12].each_with_index do |expected, index|
					character = CharacterSheet.new(character_list[index])
					#p "Level - #{character.level}, Tier - #{character.tier}, Dex - #{character.dex}, #{rules["advancement"]["competency"]["combat_pool"]}"
					expect(character.combat_pool).to eq(expected)
				end
			end
		end
	end
end
