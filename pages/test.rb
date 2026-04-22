# Sinatra routes for the /test stub-preview page. Loaded from app.rb.
# The POST handler stores the submitted form values in the session
# and 303-redirects to the GET, which keeps the submitted parameters
# off the URL while still letting the form re-render with the current
# values.

get '/test' do
  @test_params = session[:test_params] || {}
  erb :"pages/test"
end

post '/test' do
  session[:test_params] = {
    'check_name'      => params[:check_name].to_s,
    'dice_count'      => params[:dice_count].to_s,
    'tn'              => params[:tn].to_s,
    'starting_value'  => params[:starting_value].to_s,
    'luck_amount'     => params[:luck_amount].to_s,
    'insight_amount'  => params[:insight_amount].to_s
  }
  redirect '/test'
end
