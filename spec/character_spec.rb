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
end
