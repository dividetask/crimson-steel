require 'sinatra'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
set :erb, escape_html: false

get '/' do
  redirect '/test'
end

get '/test' do
  erb :test
end
