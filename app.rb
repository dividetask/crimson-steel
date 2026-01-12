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
	Combat.update(id, {mana: -1 * params[:amount].to_i})
  redirect '/combat'
end

post '/combat/dice/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
	Combat.update(id, {combat_pool:  -1 * params[:amount].to_i})
  redirect '/combat'
end

post '/combat/sat/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
	Combat.update(id, {saturation: params[:amount]})
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
  character_list = Tools.load_json('characters.json').select { |character| character["group"] == "PC" }

  halt 404, "No characters found" if character_list.empty?
  index = params[:index].to_i

  # Wrap around if index is out of bounds
  index = index % character_list.length

  @total_characters = character_list.length
  @prev_index = (index - 1) % character_list.length
  @next_index = (index + 1) % character_list.length

  @character = get_info(character_list[index])
	@compendium = Compendium.new

  @current_index = index
  @route_prefix = '/character'

  erb :character_sheet
end

get '/all_characters/:index' do
  redirect '/character/0' unless local_request?
  character_list = Tools.load_json('characters.json')

  halt 404, "No characters found" if character_list.empty?
  index = params[:index].to_i

  # Wrap around if index is out of bounds
  index = index % character_list.length

  @total_characters = character_list.length
  @prev_index = (index - 1) % character_list.length
  @next_index = (index + 1) % character_list.length

  @character = get_info(character_list[index])
	@compendium = Compendium.new

  @current_index = index
  @route_prefix = '/all_characters'

  erb :character_sheet
end
