post '/view-as/toggle' do
  halt 403 unless dm_host?
  session[:view_as_player] = !session[:view_as_player]
  redirect(request.referer || '/')
end
