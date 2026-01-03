require_relative '../helpers'
require_relative 'spec_tools.rb'
require 'json'

RSpec.describe CharacterSheet do
  let(:character_list) { SpecData.get_characters }

	describe '#Throwing things at the wall' do
		context 'praying' do
			it 'should work' do
				p ''
				character_list.each do |character_data|
					character = CharacterSheet.new(character_data)
					character.item_list.each do |item_data|
						p "#{item_data["name"]} #{item_data["description"].to_s}"
					end
				end
			end
		end
	end
end
