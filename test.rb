require 'sinatra'
require 'json'
require_relative 'helpers'

helpers CharacterHelpers

characters = Tools.load_json('characters.json')
index = 0

@character = CharacterSheet.new(characters[index])


p @character.skill_list
@character.skill_list.each do |skill_name|
	p '---'
	p @character.clean_skill_name(skill_name)
	p @character.skill_ranks(skill_name)
	p @character.skill_dice(skill_name)
	p @character.add_plus(:skill_bonus,skill_name)
	p '---'
end
