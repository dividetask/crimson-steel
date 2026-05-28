# Chronicle mutation endpoints — DM only. Used by the Encounter and
# Notes pages to add/edit/delete Entries, manage Chapters, advance
# time, and upload images. Each route persists through Chronicle's
# Store and redirects the DM back to the calling page.

helpers do
  def chronicle_store
    Chronicle.store
  end

  def viewer_role
    dm_view? ? :dm : :player
  end

  # The Creature the current viewer "is", for visibility filtering.
  # Players don't have logins, so for now everyone on the LAN is
  # treated as a single shared player Creature. The DM has no
  # viewing Creature ID (full visibility); when the DM is viewing
  # as a player, we surface the first player Creature.
  def viewing_creature_id
    return nil if viewer_role == :dm
    Creatures.player_controlled.first&.dig(:id)
  end

  def player_creatures
    Creatures.player_controlled
  end

  # Resolve a Creature Reference Entry's display name and tier from
  # the Creatures domain, honoring any Entry-level tier override.
  def resolve_creature_for(entry)
    cid  = entry['creature_id']
    info = Creatures.get(cid) || { name: "Creature ##{cid}", tier: nil }
    tier = entry['tier'] || info[:tier]
    name = info[:name]
    title = entry['title'].to_s.strip
    full = title.empty? ? name : "#{name}, #{title}"
    { name: name, full_title: full, tier: tier }
  end

  def parse_chapter(value)
    return nil if value.nil? || value.to_s.empty?
    Integer(value)
  rescue ArgumentError
    nil
  end

  def parse_bool(value)
    value.to_s == 'true' || value.to_s == '1' || value.to_s == 'on'
  end

  def parse_hidden_from(values)
    Array(values).map { |v| Integer(v) }
  rescue ArgumentError
    []
  end
end

before '/chronicle/*' do
  halt 403 unless dm_view?
end

# ---------- Time advance ----------

post '/chronicle/advance-time' do
  rounds = params[:rounds].to_i
  days   = params[:days].to_i
  chronicle_store.advance_time(rounds: rounds, days: days)
  redirect(request.referer || '/encounter')
end

# ---------- Campaign name ----------

post '/chronicle/campaign-name' do
  chronicle_store.campaign_name = params[:campaign_name].to_s
  redirect(request.referer || '/notes')
end

# ---------- Chapters ----------

post '/chronicle/chapters' do
  number = parse_chapter(params[:number]) || (chronicle_store.list_chapters.map { |c| c[:number] }.max || 0) + 1
  name   = params[:name].to_s
  begin
    chronicle_store.add_chapter(number: number, name: name)
  rescue ArgumentError
    # Chapter already exists — silently ignore for the UI.
  end
  redirect(request.referer || '/notes')
end

post '/chronicle/chapters/:number/rename' do
  chronicle_store.rename_chapter(params[:number].to_i, params[:name].to_s)
  redirect(request.referer || '/notes')
end

post '/chronicle/chapters/:number/delete' do
  chronicle_store.remove_chapter(params[:number].to_i)
  redirect(request.referer || '/notes')
end

post '/chronicle/current-chapter/advance' do
  chronicle_store.advance_chapter
  redirect(request.referer || '/notes')
end

post '/chronicle/current-chapter' do
  chronicle_store.current_chapter = params[:number].to_i
  redirect(request.referer || '/notes')
end

# ---------- Entries ----------

post '/chronicle/entries' do
  attrs = build_entry_attrs_from_params(params, owner_override: nil)
  chronicle_store.add_entry(attrs)
  redirect(request.referer || '/notes')
end

post '/chronicle/entries/:id' do
  id = params[:id].to_i
  updates = build_entry_updates_from_params(params)
  chronicle_store.edit_entry(id, updates) unless updates.empty?
  redirect(request.referer || '/notes')
end

post '/chronicle/entries/:id/delete' do
  id = params[:id].to_i
  entry = chronicle_store.get_entry(id)
  Uploads.remove(entry['image']) if entry && entry['image']
  Uploads.remove(entry['creature_token']) if entry && entry['creature_token']
  chronicle_store.delete_entry(id)
  redirect(request.referer || '/notes')
end

post '/chronicle/entries/:id/image' do
  id = params[:id].to_i
  entry = chronicle_store.get_entry(id)
  halt 404 unless entry

  field =
    case params[:field].to_s
    when 'creature_token' then 'creature_token'
    else 'image'
    end

  if params[:clear].to_s == 'true'
    Uploads.remove(entry[field])
    chronicle_store.edit_entry(id, field => nil)
  elsif params[:file]
    Uploads.remove(entry[field])
    url = Uploads.store(params[:file])
    chronicle_store.edit_entry(id, field => url) if url
  end

  redirect(request.referer || '/notes')
end

post '/chronicle/entries/:id/scene-position' do
  chronicle_store.set_scene_position(params[:id].to_i, params[:position].to_i)
  redirect(request.referer || '/encounter')
end

post '/chronicle/entries/:id/notes-position' do
  chronicle_store.set_notes_position(params[:id].to_i, params[:position].to_i)
  redirect(request.referer || '/notes')
end

# ---------- Helper to assemble form params into Entry attrs ----------

helpers do
  def build_entry_attrs_from_params(params, owner_override: nil)
    type = params[:entry_type].to_s
    base = {
      entry_type:         type,
      chapter:            parse_chapter(params[:chapter]) || chronicle_store.current_chapter,
      title:              params[:title].to_s,
      public_description: params[:public_description].to_s,
      dm_description:     params[:dm_description].to_s,
      image:              nil,
      shared:             parse_bool(params[:shared]),
      hidden_from:        parse_hidden_from(params[:hidden_from]),
      owner_id:           parse_chapter(params[:owner_id]),
      active:             parse_bool(params[:active])
    }
    base[:owner_id] = owner_override unless owner_override.nil?

    if params[:image]
      base[:image] = Uploads.store(params[:image])
    end

    if type == 'creature'
      base[:creature_id]    = parse_chapter(params[:creature_id])
      base[:creature_token] = params[:creature_token] ? Uploads.store(params[:creature_token]) : nil
      base[:tier]           = parse_chapter(params[:tier])
    end

    base
  end

  def build_entry_updates_from_params(params)
    updates = {}
    %w[title public_description dm_description].each do |f|
      updates[f] = params[f].to_s if params.key?(f)
    end
    if params.key?(:chapter)
      ch = parse_chapter(params[:chapter])
      updates['chapter'] = ch if ch
    end
    %w[shared active].each do |f|
      updates[f] = parse_bool(params[f]) if params.key?(f)
    end
    if params[:visibility_form]
      all_ids     = parse_hidden_from(params[:all_pc_ids])
      visible_ids = parse_hidden_from(params[:visible_to])
      updates['hidden_from'] = all_ids - visible_ids
    elsif params.key?(:hidden_from)
      updates['hidden_from'] = parse_hidden_from(params[:hidden_from])
    end
    if params.key?(:tier)
      updates['tier'] = params[:tier].to_s.empty? ? nil : params[:tier].to_i
    end
    updates
  end
end
