require_relative '../helpers'
require 'json'

RSpec.describe CharacterSheet do
	let(:rules) { JSON.parse(File.read('spec/fixtures/rules.json')) }
	let(:character_list) { JSON.parse(File.read('spec/fixtures/characters.json')) }

	describe '#CharacterSheet' do
		context 'Lookup static details' do
			it 'finds name, and player info' do
				[{name: 'Joe', player: 'Blow'}, {name: 'Kevin', player: 'Quan'}].each_with_index do |expected, index|
					character = CharacterSheet.new(character_list[index])
					expect(character.name).to eq(expected[:name])
					expect(character.player).to eq(expected[:player])
				end
			end

			it 'finds deity' do
				character = CharacterSheet.new(character_list[0])
				expect(character.deity).to eq('Gorum')
			end

			it 'gracefully handles null dieties' do
				character = CharacterSheet.new(character_list[1])
				expect(character.deity).to eq(nil)
			end

			it 'correctly displays race' do
				['Hill dwarf', 'Human'].each_with_index do |expected_race, index|
					character = CharacterSheet.new(character_list[index])
					expect(character.race).to eq(expected_race)
				end
			end
		end
	end
end
