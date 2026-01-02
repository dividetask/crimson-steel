require_relative '../helpers'
require_relative 'spec_tools.rb'
require 'json'

RSpec.describe CharacterSheet do
	let(:rules) { JSON.parse(File.read('spec/fixtures/rules.json')) }
	let(:character_list) { JSON.parse(File.read('spec/fixtures/characters.json')) }

				#['cleric', 'barbarian', 'fighter'].each do |klass_name|
					#test_level = (1..20).to_a.sample
					#test_klass = SingleKlassProgress.force_values(klass_name, test_level, [])
					#character.instance_variable_set(:@klass_list, [test_klass])

	describe '#TierMath' do
		context 'tier' do
			it 'tier is correct' do
				current_tier = 0
				tier_rules = [4, 9, 12, 16, 20]
				character = CharacterSheet.new(character_list.first)

				character.instance_variable_set(:@rules, {"advancement" => {"tier" => tier_rules} })
				test_level = (1..25).to_a.each do |level|

					allow(character).to receive(:level).and_return(level)
					current_tier = current_tier + 1 if tier_rules[current_tier] and level >= tier_rules[current_tier]
					expect(character.tier).to eq(current_tier)
				end
			end
		end
	end

	describe '#Skills' do
		context "skills_match?" do
			it "Handles skill categories" do
				expect(Skills.skills_match?("acrobatics", "acrobatics")).to eq(true)
				expect(Skills.skills_match?("perform_", "perform_dance")).to eq(true)
				expect(Skills.skills_match?("perform_d", "perform_dance")).to eq(false)
			end

			it "Handles skill_group" do
				expect(Skills.skill_group("acrobatics", rules)).to eq("acrobatics")
				expect(Skills.skill_group("perform_dance", rules)).to eq("perform_")
			end

			it "Handles skill_attr" do
				expect(Skills.skill_attr("acrobatics", rules)).to eq(:dex)
				expect(Skills.skill_attr("perform_dance", rules)).to eq(:cha)
			end
		end
	end

	describe '#CharacterSheet' do
		context 'Verify code runs without crash' do
			it 'has base methods defined' do
				character = CharacterSheet.new(character_list.first)
				method_list = [:name, :player, :deity, :race, :speed, :damage_reduction, :damage_resiliance, :add_plus]
				method_list.each do |method_sym|
					expect(character).to respond_to(method_sym), 
						"Expected CharacterSheet to have method :#{method_sym}"
				end

				expect(character.private_methods).to include(:parse_formula),
					"Expected CharacterSheet to have private method parse_formula"
			end

			it 'returns realistic values' do
				character_list.each do |character_data|
					character = CharacterSheet.new(character_data)

					SpecData.simple_test(character.name, String, {length: {min: 2}})
					SpecData.simple_test(character.deity, String, {length: {min: 2}})
					SpecData.simple_test(character.race, String, {length: {min: 2}})
					SpecData.simple_test(character.speed, Integer, {value: {min: 5, max: 80}})
					SpecData.simple_test(character.damage_reduction, Integer, {value: {min: 0, max: 100}})
					SpecData.simple_test(character.damage_resiliance, Integer, {value: {min: 0, max: 100}})
					allow(character).to receive(:name).and_return(5)
					SpecData.simple_test(character.add_plus(:name), String, {value: {prefix: ['+', '-']}})
				end
			end
		end

		context 'Verify results for add_plus' do
			it 'returns negative numbers as a string' do
				character = CharacterSheet.new(character_list.first)

				(-5..-1).to_a.each do |sample_int| 
					allow(character).to receive(:name).and_return(sample_int)
					expect(character.add_plus(:name)).to eq(sample_int.to_s)
				end
			end
			it 'adds a plus sign to positive numbers' do
				character = CharacterSheet.new(character_list.first)

				(0..5).to_a.each do |sample_int| 
					allow(character).to receive(:name).and_return(sample_int)
					expect(character.add_plus(:name)).to eq("+#{sample_int}")
				end
			end
		end

		context 'Verify results for parse_formula' do
			it 'returns negative numbers as a string' do
				character = CharacterSheet.new(character_list.first)
				formulas_result_hash = {
					"4+((attr/2)%5)" => {2 => 5, 5 => 6, 12 => 5}, 
					"(attr/10)-1" => {3 => -1, 12 => 0, 15 => 0, 21 => 1, 45 => 3} }
				formulas_result_hash.each do |formula, expected_hash|
					expected_hash.each do |attr_val, expected|
						expect(character.send(:parse_formula, formula, {"attr" => attr_val})).to eq(expected)
					end
				end
			end
		end
	end
end
