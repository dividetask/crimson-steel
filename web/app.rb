require 'sinatra'
require 'json'
require_relative 'helpers'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')

helpers CharacterHelpers

get '/' do
  characters = load_json('characters.json')['characters']
  halt 404, "No characters found" if characters.empty?

  @character = characters[0]
  @stats = calculate_stats(@character)
  @current_index = 0
  @total_characters = characters.length
  @prev_index = characters.length - 1
  @next_index = 1 % characters.length

  erb :character_sheet
end

get '/character/:index' do
  characters = load_json('characters.json')['characters']
  index = params[:index].to_i

  halt 404, "No characters found" if characters.empty?

  # Wrap around if index is out of bounds
  index = index % characters.length

  @character = characters[index]
  @stats = calculate_stats(@character)
  @current_index = index
  @total_characters = characters.length
  @prev_index = (index - 1) % characters.length
  @next_index = (index + 1) % characters.length

  erb :character_sheet
end
