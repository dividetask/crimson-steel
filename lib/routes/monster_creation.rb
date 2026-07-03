require_relative '../monster_creation'

# Quick Monster builder — the DM's fast "stub enemy" wizard, reached from the
# DM Page. DM-only; players are bounced to the default landing page. Stands up
# an enemy template Creature so an unlisted monster can be added to Combat
# without hand-authoring a data file mid-session.
get '/monster-creation' do
  redirect '/character-sheets' unless dm_view?
  @blob   = MonsterCreation.blob
  @form   = {}
  @error  = nil
  erb :monster_creation
end

post '/monster-creation' do
  halt 403 unless dm_view?
  begin
    id = MonsterCreation.create!(monster_params(params))
    redirect "/character-sheets?creature_id=#{id}"
  rescue ArgumentError => e
    @blob  = MonsterCreation.blob
    @form  = monster_params(params)
    @error = e.message
    status 422
    erb :monster_creation
  end
end

helpers do
  # Normalize the flat form params into the string-keyed shape
  # MonsterCreation.create! expects (and that the form re-echoes on error).
  def monster_params(params)
    attrs = {}
    Array(MonsterCreation.attribute_keys).each { |k| attrs[k] = params["attr_#{k}"] }
    {
      'name'       => params[:name].to_s,
      'race'       => params[:race].to_s,
      'class'      => params[:class].to_s,
      'level'      => params[:level].to_s,
      'tier'       => params[:tier].to_s,
      'hide_tier'  => params[:hide_tier].to_s,
      'token'      => params[:token].to_s,
      'attributes' => attrs,
      'skills'     => Array(params[:skills]).map(&:to_s).reject(&:empty?)
    }
  end
end
