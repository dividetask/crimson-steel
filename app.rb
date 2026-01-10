require 'sinatra'
require 'json'
require_relative 'helpers'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')

helpers CharacterHelpers

get '/combat' do
  redirect '/character/0' unless local_request?
  @combat = Combat.new()
  erb :combat_tracker
end

post '/combat/damage/:id' do
  redirect '/character/0' unless local_request?
  
  id = params[:id].to_i
	Combat.update(id, params.slice('minor_damage', 'moderate_damage', 'major_damage'))
  redirect '/combat'
end

post '/combat/mana/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
	Combat.update(id, {mana: params[:amount]})
  redirect '/combat'
end

post '/combat/dice/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
	Combat.update(id, {combat_pool: params[:amount]})
  redirect '/combat'
end

post '/combat/reset_dice' do
  redirect '/character/0' unless local_request?
  combat = Combat.new()
	combat.new_turn
  redirect '/combat'
end

post '/combat/reroll_init' do
  redirect '/character/0' unless local_request?
  combat = Combat.new()
	combat.reroll_init
  redirect '/combat'
end

def local_request?
  request.ip == "127.0.0.1" || request.ip == "::1" || request.ip == "localhost"
end

get '/' do
  redirect '/character/0'
end

get '/character/:index' do
  characters = Tools.load_json('characters.json')
  halt 404, "No characters found" if characters.empty?
  index = params[:index].to_i

  # Wrap around if index is out of bounds
  index = index % characters.length

  @total_characters = characters.length
  @prev_index = (index - 1) % characters.length
  @next_index = (index + 1) % characters.length

  @character = get_info(characters[index])
	@compendium = Compendium.new

  @current_index = index

  erb :character_sheet
end
