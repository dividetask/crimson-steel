require 'sinatra'
require 'json'
require_relative 'helpers'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')

helpers CharacterHelpers


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
  @current_index = index

  erb :character_sheet
end
