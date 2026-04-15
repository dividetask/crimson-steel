require 'sinatra'
require 'json'
require 'securerandom'
require 'fileutils'
require_relative 'helpers'
require_relative 'templates'

set :port, 4567
set :bind, '0.0.0.0'
set :views, File.join(__dir__, 'views')
set :public_folder, File.join(__dir__, 'public')
set :erb, escape_html: false

enable :sessions

helpers CharacterHelpers

def local_request?
  request.ip == "127.0.0.1" || request.ip == "::1" || request.ip == "localhost"
end

# Recursively walks a properties_template hash, replacing any "{placeholder}"
# string leaf with the matching field from the variant row. Numeric variant
# values come through as integers; strings stay as strings. Used by the
# store purchase flow to synthesize properties.enhancement from a single
# template plus the selected variant's amount / attribute_key.
def resolve_properties_template(template, variant)
  case template
  when Hash
    template.each_with_object({}) { |(k, v), h| h[k] = resolve_properties_template(v, variant) }
  when Array
    template.map { |v| resolve_properties_template(v, variant) }
  when String
    m = template.match(/\A\{(\w+)\}\z/)
    m ? variant[m[1]] : template.gsub(/\{(\w+)\}/) { variant[$1].to_s }
  else
    template
  end
end

# Human-readable label for an enhancement bonus payload; used in combat log
# lines ("+4 str", "+1 save") so the DM can see what effect just landed.
def enhancement_log_label(enhancement)
  amount = enhancement["amount"].to_i
  if enhancement["type"] == "attribute"
    "+#{amount} #{enhancement["attribute"]}"
  else
    "+#{amount} save"
  end
end

# Append a duration-bound active_effect carrying the resolved enhancement
# payload. The target's CharacterSheet picks up `enhancement` via
# active_effects_targeting_me, and the existing start_of_turn cleanup in
# /combat action=start_of_turn clears the entry when ends_on_round hits.
# Shared by the direct-cast, potion, and scroll item-use paths.
def apply_enhancement_effect(combat_data, effect, _target, user_character, target_character, target_ids, target_names, caster_combat_id)
  campaign = Tools.load_json('campaign.json')
  rounds_elapsed_now = campaign.is_a?(Hash) ? campaign['rounds_elapsed'].to_i : 0
  duration = [effect[:duration_rounds].to_i, 1].max
  combat_data['active_effects'] ||= []
  combat_data['active_effects'] << {
    'caster_id' => caster_combat_id,
    'caster_name' => user_character ? user_character.name : nil,
    'spell_name' => effect[:variant_name] || effect[:base_name],
    'spell_tier' => effect[:tier_val],
    'round_cast' => combat_data['round'],
    'target_combat_ids' => target_ids,
    'target_names' => target_names,
    'ends_on_round' => rounds_elapsed_now + duration,
    'enhancement' => effect[:enhancement]
  }
end

before do
  @is_local = local_request?
  @view_as_player = local_request? && session[:view_mode] == 'player'
  @is_local = false if @view_as_player
end

post '/view_mode' do
  redirect '/' unless local_request?
  session[:view_mode] = params[:mode]
  referrer = request.referrer || '/'
  if params[:mode] == 'dm' && referrer =~ /\/notes\/\d+/
    redirect '/notes/0'
  elsif params[:mode] == 'dm' && referrer =~ /\/scene(\/|$)/
    redirect '/scene/0'
  elsif params[:mode] == 'player' && referrer =~ /\/scene(\/|$)/
    redirect '/scene/1'
  else
    redirect back
  end
end

def load_character_view(character_list, index, route_prefix)
  halt 404, "No characters found" if character_list.empty?
  index = index % character_list.length

  @total_characters = character_list.length
  @prev_index = (index - 1) % character_list.length
  @next_index = (index + 1) % character_list.length

  @character = get_info(character_list[index])
  @compendium = Compendium.new

  @current_index = index
  @route_prefix = route_prefix

  erb :character_sheet
end

get '/combat' do
  redirect '/character/0' unless local_request?
  @combat = Combat.new()
  erb :combat_tracker
end

# Scene: shared player/DM view. During combat, shows a simplified initiative
# table (names, HP, initiative rolls) with enemy identities masked behind
# "DM" + a HP color band, plus the current PC's character sheet when it's
# a player's turn. Outside combat, initiative hides and players see whatever
# the DM has shared: per-player scene panels and/or shared reference images.
# The DM (local) also gets a staging block for names, draft notes, scene
# panels, and images -- none of which are visible to players.
get '/scene' do
  redirect "/scene/#{@is_local ? 0 : 1}"
end

SCENE_IMAGE_DIR = File.join(__dir__, 'public', 'images', 'scene')
SCENE_IMAGE_EXTS = %w[.png .jpg .jpeg .gif .webp].freeze
SCENE_IMAGE_MAX_BYTES = 10 * 1024 * 1024

def scene_sanitize_filename(name)
  base = File.basename(name.to_s)
  base.gsub(/[^A-Za-z0-9._-]/, '_')
end

def scene_find_note(notes, id)
  notes.each_with_index do |n, i|
    return [n, i] if n['id'] == id
  end
  [nil, nil]
end

def scene_load_notes
  Tools.load_json('notes.json')
end

def scene_save_notes(notes)
  Tools.save_json('notes.json', notes)
end

def scene_max_chapter(notes)
  notes.map { |n| n['chapter'] }.compact.max || 1
end

def scene_require_dm!
  halt 403, 'DM only' unless local_request?
end

def scene_parse_visible_to(raw)
  Array(raw).map { |v| v.to_i }.reject { |v| v <= 0 }.uniq
end

get '/scene/:viewer_id' do
  viewer_id = params[:viewer_id].to_i
  redirect '/scene/1' if viewer_id == 0 && !@is_local

  @viewer_id = viewer_id
  @is_dm = viewer_id == 0 && @is_local

  @combat = Combat.new
  @compendium = Compendium.new

  combat_data = Tools.load_json('combat.json')
  @combat_active = combat_data['active'] ? true : false
  @hide_initiative = combat_data['hide_initiative'] ? true : false
  @show_initiative = !@hide_initiative

  current = @combat.current_turn_character
  if current && current.character.data['group'] == 'PC'
    @character = current.character
    @route_prefix = nil # suppress the navigation widget in character_sheet
  else
    @character = nil
  end

  @notes = scene_load_notes
  @max_chapter = scene_max_chapter(@notes)

  @draft_names = @notes.select { |n| n['draft'] && n['type'] == 'draft_name' }
  @draft_notes = @notes.select { |n| n['draft'] && n['type'] == 'draft_note' }
  @draft_images = @notes.select { |n| n['draft'] && n['type'] == 'draft_image' }
  @scene_panels = @notes.select { |n| n['draft'] && n['type'] == 'scene_panel' }

  @visible_images = @draft_images.select { |i| i['shared'] }
  @visible_panels =
    if @is_dm
      @scene_panels
    else
      @scene_panels.select { |p| Array(p['visible_to']).include?(@viewer_id) }
    end

  characters = Tools.load_json('characters.json')
  @pc_characters = characters.select { |c| (c['group'] || 'PC') == 'PC' }

  erb :scene
end

# --- Initiative visibility toggle ---
post '/scene/toggle_initiative' do
  scene_require_dm!
  combat_data = Tools.load_json('combat.json')
  combat_data['hide_initiative'] = !combat_data['hide_initiative']
  Tools.save_json('combat.json', combat_data)
  redirect '/scene/0'
end

# --- Draft names (added in bulk; one per line in the `titles` textarea) ---
post '/scene/draft_names_bulk' do
  scene_require_dm!
  raw = params[:titles].to_s
  titles = raw.split(/[\r\n]+/).map(&:strip).reject(&:empty?)
  redirect '/scene/0' if titles.empty?
  notes = scene_load_notes
  titles.each do |title|
    notes << {
      'id' => SecureRandom.uuid,
      'owner_id' => 0,
      'draft' => true,
      'type' => 'draft_name',
      'title' => title
    }
  end
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/draft_name/delete' do
  scene_require_dm!
  notes = scene_load_notes
  _, idx = scene_find_note(notes, params[:id])
  halt 404 unless idx
  notes.delete_at(idx)
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/draft_name/update' do
  scene_require_dm!
  title = params[:title].to_s.strip
  halt 400, 'title required' if title.empty?
  notes = scene_load_notes
  entry, _ = scene_find_note(notes, params[:id])
  halt 404 unless entry && entry['type'] == 'draft_name'
  entry['title'] = title
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/draft_name/promote' do
  scene_require_dm!
  notes = scene_load_notes
  entry, idx = scene_find_note(notes, params[:id])
  halt 404 unless entry && entry['type'] == 'draft_name'
  note_body = params[:note].to_s
  tier = params[:tier] ? params[:tier].to_i : -1
  public_flag = params[:public] == 'true'
  promoted = {
    'owner_id' => 0,
    'type' => 'character',
    'title' => entry['title'],
    'note' => note_body,
    'tier' => tier,
    'chapter' => scene_max_chapter(notes),
    'public' => public_flag,
    'active' => true
  }
  notes[idx] = promoted
  scene_save_notes(notes)
  redirect '/scene/0'
end

# --- Draft notes (prep scratchpad; never shown on /scene) ---
post '/scene/draft_note' do
  scene_require_dm!
  notes = scene_load_notes
  entry = {
    'id' => SecureRandom.uuid,
    'owner_id' => 0,
    'draft' => true,
    'type' => 'draft_note',
    'title' => params[:title].to_s,
    'note' => params[:note].to_s,
    'public' => params[:public] == 'true'
  }
  notes << entry
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/draft_note/update' do
  scene_require_dm!
  notes = scene_load_notes
  entry, idx = scene_find_note(notes, params[:id])
  halt 404 unless entry && entry['type'] == 'draft_note'
  entry['title'] = params[:title].to_s
  entry['note'] = params[:note].to_s
  entry['public'] = params[:public] == 'true'
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/draft_note/delete' do
  scene_require_dm!
  notes = scene_load_notes
  _, idx = scene_find_note(notes, params[:id])
  halt 404 unless idx
  notes.delete_at(idx)
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/draft_note/promote' do
  scene_require_dm!
  notes = scene_load_notes
  entry, idx = scene_find_note(notes, params[:id])
  halt 404 unless entry && entry['type'] == 'draft_note'
  promoted = {
    'owner_id' => 0,
    'type' => 'note',
    'title' => entry['title'].to_s,
    'note' => entry['note'].to_s,
    'chapter' => scene_max_chapter(notes),
    'public' => entry['public'] ? true : false
  }
  notes[idx] = promoted
  scene_save_notes(notes)
  redirect '/scene/0'
end

# --- Scene panels (per-player visibility; shown on /scene) ---
post '/scene/panel' do
  scene_require_dm!
  notes = scene_load_notes
  notes << {
    'id' => SecureRandom.uuid,
    'owner_id' => 0,
    'draft' => true,
    'type' => 'scene_panel',
    'title' => params[:title].to_s,
    'note' => params[:note].to_s,
    'visible_to' => scene_parse_visible_to(params[:visible_to])
  }
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/panel/update' do
  scene_require_dm!
  notes = scene_load_notes
  entry, _ = scene_find_note(notes, params[:id])
  halt 404 unless entry && entry['type'] == 'scene_panel'
  entry['title'] = params[:title].to_s
  entry['note'] = params[:note].to_s
  entry['visible_to'] = scene_parse_visible_to(params[:visible_to])
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/panel/delete' do
  scene_require_dm!
  notes = scene_load_notes
  _, idx = scene_find_note(notes, params[:id])
  halt 404 unless idx
  notes.delete_at(idx)
  scene_save_notes(notes)
  redirect '/scene/0'
end

# --- Images ---
post '/scene/image' do
  scene_require_dm!
  upload = params[:image]
  halt 400, 'image required' unless upload.is_a?(Hash) && upload[:tempfile]
  orig = upload[:filename] || 'upload'
  ext = File.extname(orig).downcase
  halt 400, 'unsupported file type' unless SCENE_IMAGE_EXTS.include?(ext)
  halt 400, 'file too large' if upload[:tempfile].size > SCENE_IMAGE_MAX_BYTES

  FileUtils.mkdir_p(SCENE_IMAGE_DIR)
  safe_base = scene_sanitize_filename(File.basename(orig, ext))
  filename = "#{Time.now.to_i}-#{SecureRandom.hex(4)}-#{safe_base}#{ext}"
  dest = File.join(SCENE_IMAGE_DIR, filename)
  FileUtils.cp(upload[:tempfile].path, dest)

  notes = scene_load_notes
  notes << {
    'id' => SecureRandom.uuid,
    'owner_id' => 0,
    'draft' => true,
    'type' => 'draft_image',
    'title' => params[:title].to_s,
    'image_path' => "/images/scene/#{filename}",
    'shared' => false
  }
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/image/share' do
  scene_require_dm!
  notes = scene_load_notes
  entry, _ = scene_find_note(notes, params[:id])
  halt 404 unless entry && entry['type'] == 'draft_image'
  entry['shared'] = !entry['shared']
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/image/update' do
  scene_require_dm!
  notes = scene_load_notes
  entry, _ = scene_find_note(notes, params[:id])
  halt 404 unless entry && entry['type'] == 'draft_image'
  entry['title'] = params[:title].to_s
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/image/delete' do
  scene_require_dm!
  notes = scene_load_notes
  entry, idx = scene_find_note(notes, params[:id])
  halt 404 unless entry && entry['type'] == 'draft_image'
  path = entry['image_path'].to_s
  if path.start_with?('/images/scene/')
    disk = File.join(__dir__, 'public', path)
    File.unlink(disk) if File.file?(disk)
  end
  notes.delete_at(idx)
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/scene/image/promote' do
  scene_require_dm!
  notes = scene_load_notes
  entry, idx = scene_find_note(notes, params[:id])
  halt 404 unless entry && entry['type'] == 'draft_image'
  promoted = {
    'owner_id' => 0,
    'type' => 'image',
    'title' => entry['title'].to_s,
    'image_path' => entry['image_path'],
    'chapter' => scene_max_chapter(notes),
    'public' => true
  }
  notes[idx] = promoted
  scene_save_notes(notes)
  redirect '/scene/0'
end

post '/combat/update/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
  Combat.update(id, {
    'minor_damage' => params[:minor_damage],
    'moderate_damage' => params[:moderate_damage],
    'major_damage' => params[:major_damage],
    'mana' => params[:mana],
    'combat_pool' => params[:combat_pool],
    'saturation' => params[:saturation],
    'temporary_hit_points' => params[:temporary_hit_points]
  }, set_keys: %w[minor_damage moderate_damage major_damage mana combat_pool saturation temporary_hit_points])
  redirect '/combat'
end

post '/combat/sat/:id' do
  redirect '/character/0' unless local_request?
  id = params[:id].to_i
  Combat.update(id, {saturation: params[:amount]}, set_keys: ['saturation'])
  redirect '/combat'
end

post '/combat/reset_dice' do
  redirect '/character/0' unless local_request?
  combat = Combat.new()
  combat.new_turn
  redirect '/combat'
end

post '/combat/action' do
  redirect '/character/0' unless local_request?
  combat = Combat.new
  combat_data = Tools.load_json('combat.json')
  combat_id = params[:id].to_i
  action = params[:combat_action]

  if action == 'attack'
    attacker_combat_id = params[:attacker_combat_id].to_i
    target_combat_id = params[:target_combat_id].to_i
    attacker_dice_spent = params[:attacker_dice_spent].to_i
    defense_dice = params[:defense_dice].to_i
    target_mana_cost = params[:target_mana_cost].to_i
    minor = params[:minor_damage].to_i
    moderate = params[:moderate_damage].to_i
    major = params[:major_damage].to_i

    attacker = combat_data['participants'].find { |p| p['id'] == attacker_combat_id }
    target_participant = combat_data['participants'].find { |p| p['id'] == target_combat_id }
    halt 400, "Attacker not found" unless attacker
    halt 400, "Target not found" unless target_participant

    attacker['combat_pool'] = attacker['combat_pool'].to_i - attacker_dice_spent if attacker_dice_spent > 0
    target_participant['combat_pool'] = target_participant['combat_pool'].to_i - defense_dice if defense_dice > 0
    target_participant['mana'] = target_participant['mana'].to_i - target_mana_cost if target_mana_cost > 0

    incoming_total = minor + moderate + major

    # Temp HP absorbs incoming damage worst-first (major -> moderate -> minor).
    temp_hp = target_participant['temporary_hit_points'].to_i
    absorbed_major = [major, temp_hp].min; temp_hp -= absorbed_major
    absorbed_moderate = [moderate, temp_hp].min; temp_hp -= absorbed_moderate
    absorbed_minor = [minor, temp_hp].min; temp_hp -= absorbed_minor
    target_participant['temporary_hit_points'] = temp_hp
    major -= absorbed_major
    moderate -= absorbed_moderate
    minor -= absorbed_minor

    target_participant['minor_damage'] = target_participant['minor_damage'].to_i + minor
    target_participant['moderate_damage'] = target_participant['moderate_damage'].to_i + moderate
    target_participant['major_damage'] = target_participant['major_damage'].to_i + major

    # Apply per-attack conditions when the strike penetrates armor. The
    # client sets afflict='true' when pre-DR damage >= target's DR, so an
    # attack whose damage exactly matches armor still inflicts afflictions
    # even though 0 HP damage got through. A miss or damage < DR sends
    # afflict='false' and this block is skipped.
    #
    # The client computes default affliction amounts from the weapon's
    # bleed rating / attacker tier / 5+damage for poison, but the DM can
    # edit each value before submit. We trust the submitted afflict_<key>
    # values here; the client only shows inputs for afflictions that
    # would naturally apply to this attack. The attacker/weapon lookup is
    # still needed to update condition_meta.max_ghoul_tier.
    afflict = params[:afflict] == 'true'
    if afflict
      target_participant['conditions'] ||= {}
      target_participant['condition_meta'] ||= {}

      bleed_amt = params[:afflict_bleed].to_i
      if bleed_amt > 0
        target_participant['conditions']['bleed'] =
          target_participant['conditions']['bleed'].to_i + bleed_amt
      end

      gp_amt = params[:afflict_ghoul_paralysis].to_i
      if gp_amt > 0
        target_participant['conditions']['ghoul_paralysis'] =
          target_participant['conditions']['ghoul_paralysis'].to_i + gp_amt
        # Track the highest ghoul tier that has hit this target; it modifies
        # save TN until the condition decays to 0. Look up the attacker to
        # know their tier.
        if params[:weapon_item_id] && !params[:weapon_item_id].to_s.empty?
          attacker_char_id = attacker['char_id'] || attacker['id']
          attacker_data = Tools.load_json('characters.json').find { |c| c['id'] == attacker_char_id }
          if attacker_data
            attacker_tier = CharacterSheet.new(attacker_data).tier.to_i
            target_participant['condition_meta']['max_ghoul_tier'] =
              [target_participant['condition_meta']['max_ghoul_tier'].to_i, attacker_tier].max
          end
        end
      end

      poison_amt = params[:afflict_minor_strength_poison].to_i
      if poison_amt > 0
        target_participant['conditions']['minor_strength_poison'] =
          target_participant['conditions']['minor_strength_poison'].to_i + poison_amt
      end
    end

    # Subtract ally dice spent
    ally_data = params[:ally_data] || ''
    ally_data.split(';').each do |entry|
      next if entry.empty?
      aid, adice = entry.split(':').map(&:to_i)
      ally = combat_data['participants'].find { |p| p['id'] == aid }
      ally['combat_pool'] = ally['combat_pool'].to_i - adice if ally && adice > 0
    end

    # Subtract mana from Healing Word casters
    hw_data = params[:healing_word_data] || ''
    hw_data.split(';').each do |entry|
      next if entry.empty?
      hid, hcost = entry.split(':').map(&:to_i)
      healer = combat_data['participants'].find { |p| p['id'] == hid }
      healer['mana'] = healer['mana'].to_i - hcost if healer && hcost > 0
    end

    Tools.save_json('combat.json', combat_data)

    total = minor + moderate + major
    absorbed = absorbed_major + absorbed_moderate + absorbed_minor
    if total > 0 || absorbed > 0
      suffix = absorbed > 0 ? " (#{absorbed} absorbed by temp HP)" : ""
      Combat.add_log("Attack resolved: #{total} damage (#{minor}/#{moderate}/#{major})#{suffix}")
    else
      Combat.add_log("Attack missed")
    end

  elsif action == 'move'
    participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    char_id = participant['char_id'] || participant['id']
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    halt 400, "Not enough dice to move" unless participant['combat_pool'] >= 4

    participant['combat_pool'] -= 4
    Tools.save_json('combat.json', combat_data)

    Combat.add_log("#{character.name} moves")

  elsif action == 'cast'
    participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    halt 400, "Participant not found" unless participant
    char_id = participant['char_id'] || participant['id']
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    spell_name = params[:spell_name]
    spell_tier = params[:spell_tier].to_i
    mana_cost = spell_tier == 0 ? 1 : (spell_tier * 2 + 2)

    halt 400, "Not enough mana" unless participant['mana'].to_i >= mana_cost

    # Accept either a single target_combat_id or a comma-separated
    # target_combat_ids list (for multi-target spells). Single-target
    # effect branches (cure, ward) use the first id; the generic branch
    # iterates the full list.
    target_ids = if params[:target_combat_ids] && !params[:target_combat_ids].to_s.empty?
      params[:target_combat_ids].to_s.split(',').map { |s| s.strip.to_i }.reject(&:zero?)
    elsif params[:target_combat_id] && !params[:target_combat_id].to_s.empty?
      [params[:target_combat_id].to_i]
    else
      []
    end
    target_combat_id = target_ids.first

    compendium = Compendium.new
    cure = compendium.cure_effects(spell_name)
    ward = compendium.ward_effects(spell_name)
    resolved = compendium.resolve_spell_variant(spell_name)
    base_name = resolved ? resolved[0] : nil
    concentration = compendium.concentration?(spell_name)

    # Dice cost from combat pool based on casting time:
    #   casting_time == 0.5 (half action): 4 dice minimum
    #   0 < casting_time < 0.5 (bonus action): 2 dice minimum
    #   otherwise (free / main action / longer): 0
    # Stabilize asks the DM for its own dice count; the rest spend
    # min_cast_dice automatically from the pool.
    casting_time = resolved ? resolved[1]['casting_time'].to_f : 0
    min_cast_dice = if casting_time == 0.5
                      4
                    elsif casting_time > 0 && casting_time < 0.5
                      2
                    else
                      0
                    end

    if base_name == 'Stabilize'
      halt 400, "Stabilize requires a target" unless target_combat_id
      target = combat_data['participants'].find { |p| p['id'] == target_combat_id }
      halt 400, "Target not found" unless target
      target_char_id = target['char_id'] || target['id']
      target_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
      halt 400, "Target character not found" unless target_data
      target_character = CharacterSheet.new(target_data)

      dice_spent = params[:stabilize_dice].to_i
      floor = [min_cast_dice, 1].max
      halt 400, "Stabilize requires spending at least #{floor} #{floor == 1 ? 'die' : 'dice'}" if dice_spent < floor
      halt 400, "Not enough combat dice" unless participant['combat_pool'].to_i >= dice_spent

      successes = params[:stabilize_successes].to_i
      target['conditions'] ||= {}
      before = target['conditions']['bleed'].to_i
      # Stabilize description: "Reduce bleeding by 3 for each success."
      after = [before - 3 * successes, 0].max
      reduction = before - after
      if after <= 0
        target['conditions'].delete('bleed')
      else
        target['conditions']['bleed'] = after
      end

      participant['mana'] = participant['mana'].to_i - mana_cost
      participant['combat_pool'] = participant['combat_pool'].to_i - dice_spent

      # Stabilize is a concentration spell; register the effect so the DM
      # can dismiss it (or later let it tick down). Consistent shape with
      # other concentration entries so the existing dismiss/display paths
      # handle it without special-casing.
      combat_data['active_effects'] ||= []
      combat_data['active_effects'] << {
        'caster_id' => combat_id,
        'caster_name' => character.name,
        'spell_name' => spell_name,
        'spell_tier' => spell_tier,
        'round_cast' => combat_data['round'],
        'target_combat_ids' => [target_combat_id],
        'target_names' => [target_character.name]
      }

      Tools.save_json('combat.json', combat_data)
      Combat.add_log("#{character.name} casts #{spell_name} on #{target_character.name} (#{mana_cost} mana, #{dice_spent} dice, #{successes} successes) - bleed #{before} -> #{after} (-#{reduction})")
    elsif ward
      halt 400, "Ward spell requires a target" unless target_combat_id
      target = combat_data['participants'].find { |p| p['id'] == target_combat_id }
      halt 400, "Target not found" unless target
      target_char_id = target['char_id'] || target['id']
      target_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
      halt 400, "Target character not found" unless target_data
      target_character = CharacterSheet.new(target_data)

      halt 400, "Not enough combat dice (need #{min_cast_dice})" if min_cast_dice > 0 && participant['combat_pool'].to_i < min_cast_dice

      current_temp = target['temporary_hit_points'].to_i
      new_temp = [current_temp, ward[:temp_hp]].max
      target['temporary_hit_points'] = new_temp
      # How much temp HP this ward actually contributed; stored so the
      # expiry cleanup can subtract exactly this amount without stomping
      # other temp-HP sources.
      temp_hp_added = [new_temp - current_temp, 0].max

      participant['mana'] = participant['mana'].to_i - mana_cost
      participant['combat_pool'] = participant['combat_pool'].to_i - min_cast_dice if min_cast_dice > 0

      # Register the Ward as a duration-bound active effect so the
      # combat tracker can display how many rounds remain before it
      # fades. Uses the same ends_on_round machinery as paralysis; the
      # Start of Turn cleanup purges the entry when the round arrives
      # and subtracts temp_hp_added from the target's current temp HP
      # (floored at 0), so the ward's contribution is rolled back without
      # stomping other temp-HP sources.
      campaign = Tools.load_json('campaign.json')
      rounds_elapsed_now = campaign.is_a?(Hash) ? campaign['rounds_elapsed'].to_i : 0
      duration_rounds = ward[:duration_rounds].to_i
      duration_rounds = 1 if duration_rounds < 1
      combat_data['active_effects'] ||= []
      combat_data['active_effects'] << {
        'caster_id' => combat_id,
        'caster_name' => character.name,
        'spell_name' => spell_name,
        'spell_tier' => spell_tier,
        'round_cast' => combat_data['round'],
        'target_combat_ids' => [target_combat_id],
        'target_names' => [target_character.name],
        'ends_on_round' => rounds_elapsed_now + duration_rounds,
        'temp_hp_added' => temp_hp_added
      }

      Tools.save_json('combat.json', combat_data)
      Combat.add_log("#{character.name} casts #{spell_name} on #{target_character.name} (#{mana_cost} mana, #{duration_rounds} round#{'s' unless duration_rounds == 1}) - temp HP #{current_temp} -> #{new_temp}")
    elsif cure
      halt 400, "Cure spell requires a target" unless target_combat_id
      target = combat_data['participants'].find { |p| p['id'] == target_combat_id }
      halt 400, "Target not found" unless target
      target_char_id = target['char_id'] || target['id']
      target_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
      halt 400, "Target character not found" unless target_data
      target_character = CharacterSheet.new(target_data)

      max_saturation = target_character.cha
      current_saturation = target['saturation'].to_i
      if current_saturation >= max_saturation
        halt 400, "#{target_character.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})"
      end

      healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target, cure)

      # Saturation: reduce by target tier, and by 2*caster_tier if caster has improved_healing.
      # Floor at minimum_saturation.
      sat_add = cure[:saturation] - target_character.tier
      sat_add -= 2 * character.tier if character.ability_list.include?("improved_healing")
      sat_add = cure[:minimum_saturation] if sat_add < cure[:minimum_saturation]
      target['saturation'] = current_saturation + sat_add

      participant['mana'] = participant['mana'].to_i - mana_cost
      Tools.save_json('combat.json', combat_data)

      Combat.add_log("#{character.name} casts #{spell_name} on #{target_character.name} (#{mana_cost} mana) - healed #{healed_major}/#{healed_moderate}/#{healed_minor} (major/moderate/minor), +#{sat_add} saturation")
    else
      target_names = []
      target_ids.each do |tid|
        target = combat_data['participants'].find { |p| p['id'] == tid }
        next unless target
        target_char_id = target['char_id'] || target['id']
        target_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
        target_names << CharacterSheet.new(target_data).name if target_data
      end

      # Spiritual Weapon: record the number of dice spent at cast time. Those
      # dice come out of the caster's combat pool now and are "locked in" on
      # the active effect for later concentrate attacks. The dice cap is the
      # caster's Healing skill dice (Spiritual Weapon rolls off Healing).
      spiritual_weapon_dice = 0
      if spell_name == 'Spiritual Weapon'
        spiritual_weapon_dice = params[:dice_spent].to_i
        healing_cap = character.skill_dice("healing").to_i
        halt 400, "Spiritual Weapon requires a target" if target_ids.empty?
        halt 400, "Spiritual Weapon must spend at least 2 dice" if spiritual_weapon_dice < 2
        halt 400, "Not enough dice" if participant['combat_pool'].to_i < spiritual_weapon_dice
        halt 400, "Spiritual Weapon is capped at your Healing dice (#{healing_cap})" if spiritual_weapon_dice > healing_cap
        participant['combat_pool'] = participant['combat_pool'].to_i - spiritual_weapon_dice
      end

      # Blindness/Deafness: dice are spent on the spell check, success or
      # failure, and a condition (Blindness or Deafness) is applied when the
      # caster beats the target save by >= 2 net successes. Client handles
      # the opposed roll and sends bd_hit plus the chosen sub-effect.
      bd_dice = 0
      bd_effect = nil
      bd_hit = false
      if spell_name == 'Blindness/Deafness'
        halt 400, "Blindness/Deafness requires a target" if target_ids.empty?
        bd_dice = params[:dice_spent].to_i
        halt 400, "Blindness/Deafness must spend at least 2 dice" if bd_dice < 2
        halt 400, "Not enough dice" if participant['combat_pool'].to_i < bd_dice
        bd_effect = params[:bd_effect].to_s
        halt 400, "Invalid effect" unless %w[blindness deafness].include?(bd_effect)
        bd_hit = params[:bd_hit].to_s == 'true'
        participant['combat_pool'] = participant['combat_pool'].to_i - bd_dice
      end

      participant['mana'] = participant['mana'].to_i - mana_cost
      # Enhancement spells (Resistance, Bull's Strength, ...) write an
      # active_effect carrying the resolved bonus payload. The target's
      # CharacterSheet picks it up via active_effects_targeting_me so the
      # bonus shows up on saves / attributes until ends_on_round clears it
      # at the target's next Start of Turn.
      enhancement = Compendium.new.enhancement_effects(spell_name)
      if enhancement && !target_ids.empty?
        apply_enhancement_effect(combat_data, enhancement.merge(variant_name: spell_name), nil, character, nil, target_ids, target_names, combat_id)
      elsif concentration
        combat_data['active_effects'] ||= []
        effect_entry = {
          'caster_id' => combat_id,
          'caster_name' => character.name,
          'spell_name' => spell_name,
          'spell_tier' => spell_tier,
          'round_cast' => combat_data['round'],
          'target_combat_ids' => target_ids,
          'target_names' => target_names
        }
        effect_entry['dice_spent'] = spiritual_weapon_dice if spell_name == 'Spiritual Weapon'
        combat_data['active_effects'] << effect_entry
      end

      if spell_name == 'Blindness/Deafness' && bd_hit
        combat_data['active_effects'] ||= []
        combat_data['active_effects'] << {
          'caster_id' => combat_id,
          'caster_name' => character.name,
          'spell_name' => bd_effect == 'blindness' ? 'Blindness' : 'Deafness',
          'spell_tier' => spell_tier,
          'round_cast' => combat_data['round'],
          'target_combat_ids' => target_ids,
          'target_names' => target_names,
          'permanent' => true
        }
      end
      Tools.save_json('combat.json', combat_data)
      suffix = target_names.empty? ? "" : " on #{target_names.join(', ')}"
      dice_suffix = if spiritual_weapon_dice > 0
        " with #{spiritual_weapon_dice} dice"
      elsif bd_dice > 0
        " with #{bd_dice} dice"
      else
        ""
      end
      outcome = ""
      if spell_name == 'Blindness/Deafness'
        label = bd_effect == 'blindness' ? 'Blindness' : 'Deafness'
        caster_s = params[:bd_caster_successes].to_i
        save_s = params[:bd_save_successes].to_i
        outcome = bd_hit ?
          " - #{label} applied (#{caster_s} vs #{save_s} save)" :
          " - save succeeded (#{caster_s} vs #{save_s} save)"
      end
      duration_log = enhancement ? " (#{[enhancement[:duration_rounds].to_i, 1].max} round#{'s' unless enhancement[:duration_rounds].to_i == 1})" : ""
      Combat.add_log("#{character.name} casts #{spell_name}#{suffix}#{dice_suffix} (#{mana_cost} mana)#{outcome}#{duration_log}")
    end

  elsif action == 'item'
    user_participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    halt 400, "Participant not found" unless user_participant
    user_char_id = user_participant['char_id'] || user_participant['id']
    user_character_data = Tools.load_json('characters.json').find { |c| c['id'] == user_char_id }
    user_character = CharacterSheet.new(user_character_data)

    item_id = params[:item_id].to_i
    item = user_character.item_list.find { |i| i['item_id'].to_i == item_id }
    halt 400, "Item not found" unless item

    compendium = Compendium.new
    effect = compendium.item_effects(item)
    halt 400, "This item cannot be used" unless effect

    item_target_mode = effect[:target_mode].to_s
    item_target_mode = "single" if item_target_mode.empty?

    # Parse targets. Accept target_combat_ids (comma-separated) for multi-target
    # scrolls, or target_combat_id for the single-target flow. For no-target
    # items we don't require any id; otherwise default to self.
    raw_multi = params[:target_combat_ids].to_s
    target_ids = if !raw_multi.empty?
      raw_multi.split(',').map { |s| s.strip.to_i }.reject(&:zero?)
    elsif params[:target_combat_id] && !params[:target_combat_id].to_s.empty?
      [params[:target_combat_id].to_i]
    elsif item_target_mode == "none"
      []
    else
      [combat_id]
    end

    # Single-target branches (all potions, and scroll cure/ward/mana) use
    # the first target. No-target items skip resolution entirely.
    target_combat_id = target_ids.first
    if item_target_mode == "none"
      target = nil
      target_character = nil
      max_saturation = 0
      current_saturation = 0
      at_max = false
    else
      target = combat_data['participants'].find { |p| p['id'] == target_combat_id }
      halt 400, "Target not found" unless target
      target_char_id = target['char_id'] || target['id']
      target_data = Tools.load_json('characters.json').find { |c| c['id'] == target_char_id }
      halt 400, "Target character not found" unless target_data
      target_character = CharacterSheet.new(target_data)
      max_saturation = target_character.cha
      current_saturation = target['saturation'].to_i
      at_max = current_saturation >= max_saturation
    end

    effect_log = ""

    if effect[:kind] == :potion
      # Potions always cause saturation (flat potion rule), so blocked at max.
      halt 400, "#{target_character.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max

      potion_sat = Compendium.potion_saturation(effect[:item_tier], target_character.tier)

      case effect[:type]
      when :cure
        healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target, effect)
        # Cure spell saturation rules (no improved_healing for potions)
        # PLUS the potion's own saturation on top.
        cure_sat = effect[:saturation] - target_character.tier
        cure_sat = effect[:minimum_saturation] if cure_sat < effect[:minimum_saturation]
        total_sat = cure_sat + potion_sat
        target['saturation'] = current_saturation + total_sat
        effect_log = "healed #{healed_major}/#{healed_moderate}/#{healed_minor}, +#{total_sat} saturation (#{cure_sat} cure + #{potion_sat} potion)"

      when :mana
        target_max_mana = target_character.mana_max
        current_mana = target['mana'].to_i
        new_mana = [current_mana + effect[:mana], target_max_mana].min
        target['mana'] = new_mana
        target['saturation'] = current_saturation + potion_sat
        effect_log = "mana #{current_mana} -> #{new_mana}, +#{potion_sat} saturation"

      when :ward
        current_temp = target['temporary_hit_points'].to_i
        new_temp = [current_temp, effect[:temp_hp]].max
        target['temporary_hit_points'] = new_temp
        target['saturation'] = current_saturation + potion_sat
        effect_log = "temp HP #{current_temp} -> #{new_temp}, +#{potion_sat} saturation"

      when :enhancement
        apply_enhancement_effect(combat_data, effect, target, user_character, target_character, [target_combat_id], [target_character.name], combat_id)
        target['saturation'] = current_saturation + potion_sat
        effect_log = "#{enhancement_log_label(effect[:enhancement])} for #{[effect[:duration_rounds].to_i, 1].max} round#{'s' unless effect[:duration_rounds].to_i == 1}, +#{potion_sat} saturation"
      end

    elsif effect[:kind] == :scroll
      # Scrolls act like casting the underlying spell with no mana cost.
      # Full spell saturation rules apply (including improved_healing for cures),
      # and scrolls with unrecognized spell effects are still consumable.
      case effect[:type]
      when :cure
        halt 400, "#{target_character.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max

        healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target, effect)
        sat_add = effect[:saturation] - target_character.tier
        sat_add -= 2 * user_character.tier if user_character.ability_list.include?("improved_healing")
        sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
        target['saturation'] = current_saturation + sat_add
        effect_log = "healed #{healed_major}/#{healed_moderate}/#{healed_minor}, +#{sat_add} saturation"

      when :mana
        halt 400, "#{target_character.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max

        target_max_mana = target_character.mana_max
        current_mana = target['mana'].to_i
        new_mana = [current_mana + effect[:mana], target_max_mana].min
        target['mana'] = new_mana
        # Recharge is universal school, not healing -- improved_healing does not apply.
        sat_add = effect[:saturation] - target_character.tier
        sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
        target['saturation'] = current_saturation + sat_add
        effect_log = "mana #{current_mana} -> #{new_mana}, +#{sat_add} saturation"

      when :ward
        # Ward has no saturation when cast, so no max-sat block.
        current_temp = target['temporary_hit_points'].to_i
        new_temp = [current_temp, effect[:temp_hp]].max
        target['temporary_hit_points'] = new_temp
        effect_log = "temp HP #{current_temp} -> #{new_temp}"

      when :enhancement
        # Scroll-cast enhancement buffs target a single creature (the scroll
        # flow doesn't populate multi-target for this type today) and reuse
        # the same apply_enhancement_effect helper as potions / direct casts.
        apply_enhancement_effect(combat_data, effect, target, user_character, target_character, [target_combat_id], [target_character.name], combat_id)
        effect_log = "#{enhancement_log_label(effect[:enhancement])} for #{[effect[:duration_rounds].to_i, 1].max} round#{'s' unless effect[:duration_rounds].to_i == 1}"

      when :generic
        # Spell effect not yet implemented. Scroll is still consumed.
        # Collect target names (for multi-target scrolls, all selected targets).
        generic_names = []
        target_ids.each do |tid|
          p = combat_data['participants'].find { |x| x['id'] == tid }
          next unless p
          pc_id = p['char_id'] || p['id']
          pd = Tools.load_json('characters.json').find { |c| c['id'] == pc_id }
          generic_names << CharacterSheet.new(pd).name if pd
        end
        suffix = generic_names.empty? ? "" : " on #{generic_names.join(', ')}"
        effect_log = "casts #{effect[:variant_name] || item['name']}#{suffix} (no implemented effect)"
      end
    end

    # Consume one charge. item_ids in equipment.json are ephemeral positional
    # ids (i + 1), so the stored index is simply item_id - 1. Inline character
    # items use negative item_ids and live in characters.json instead.
    if item['item_id'].to_i > 0
      equipment = Tools.load_json('equipment.json')
      stored_idx = item_id - 1
      if stored_idx >= 0 && stored_idx < equipment.length
        stored = equipment[stored_idx]
        stored['quantity'] = (stored['quantity'] || 1) - 1
        equipment.delete_at(stored_idx) if stored['quantity'] <= 0
        Tools.save_json('equipment.json', equipment)
      end
    else
      # Inline item id is -(position + 1), so position is -id - 1.
      characters = Tools.load_json('characters.json')
      owner = characters.find { |c| c['id'] == user_char_id }
      if owner && owner['items']
        inline_idx = -item['item_id'].to_i - 1
        if inline_idx >= 0 && inline_idx < owner['items'].length
          inline = owner['items'][inline_idx]
          inline['quantity'] = (inline['quantity'] || 1) - 1
          owner['items'].delete_at(inline_idx) if inline['quantity'] <= 0
          Tools.save_json('characters.json', characters)
        end
      end
    end

    Tools.save_json('combat.json', combat_data)
    # Single-target branches name `target_character`; the multi-target /
    # no-target scroll-generic branch embeds names (or nothing) in effect_log.
    generic_multi_or_none = effect[:kind] == :scroll && effect[:type] == :generic && target_ids.length != 1
    log_prefix = if generic_multi_or_none || target_character.nil?
      "#{user_character.name} uses #{item['name']}"
    else
      "#{user_character.name} uses #{item['name']} on #{target_character.name}"
    end
    Combat.add_log("#{log_prefix} - #{effect_log}")

  elsif action == 'concentrate'
    participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    halt 400, "Participant not found" unless participant
    char_id = participant['char_id'] || participant['id']
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    effect_index = params[:effect_index].to_i
    combat_data['active_effects'] ||= []
    effect = combat_data['active_effects'][effect_index]
    halt 400, "Effect not found" unless effect
    halt 400, "You are not concentrating on that effect" unless effect['caster_id'] == combat_id

    sub = (params[:sub_action] || 'reapply').to_s

    new_target_ids = if params[:target_combat_ids] && !params[:target_combat_ids].to_s.empty?
      params[:target_combat_ids].to_s.split(',').map { |s| s.strip.to_i }.reject(&:zero?)
    elsif params[:target_combat_id] && !params[:target_combat_id].to_s.empty?
      [params[:target_combat_id].to_i]
    else
      []
    end

    target_names_for = ->(ids) {
      names = []
      ids.each do |tid|
        tp = combat_data['participants'].find { |p| p['id'] == tid }
        next unless tp
        tc_id = tp['char_id'] || tp['id']
        td = Tools.load_json('characters.json').find { |c| c['id'] == tc_id }
        names << CharacterSheet.new(td).name if td
      end
      names
    }

    spell_name = effect['spell_name']

    if sub == 'change_target'
      # Changing target for a concentration effect costs 4 action dice
      # (Spiritual Weapon / Shield of Faith redirect both specify a move
      # action's worth of effort).
      halt 400, "New target required" if new_target_ids.empty?
      halt 400, "Not enough dice (need 4)" unless participant['combat_pool'].to_i >= 4
      participant['combat_pool'] = participant['combat_pool'].to_i - 4
      effect['target_combat_ids'] = new_target_ids
      effect['target_names'] = target_names_for.call(new_target_ids)
      Tools.save_json('combat.json', combat_data)
      Combat.add_log("#{character.name} redirects #{spell_name} to #{effect['target_names'].join(', ')} (4 dice)")

    elsif sub == 'attack' && spell_name == 'Spiritual Weapon'
      # Spiritual Weapon attack: costs no action dice for the attacker and
      # no mana. The attack roll uses the recorded dice count. Damage split
      # is resolved client-side (same flow as a weapon attack).
      target_combat_id = new_target_ids.first || (effect['target_combat_ids'] || []).first
      halt 400, "Target required" unless target_combat_id
      target_participant = combat_data['participants'].find { |p| p['id'] == target_combat_id }
      halt 400, "Target not found" unless target_participant

      defense_dice = params[:defense_dice].to_i
      target_mana_cost = params[:target_mana_cost].to_i
      minor = params[:minor_damage].to_i
      moderate = params[:moderate_damage].to_i
      major = params[:major_damage].to_i

      target_participant['combat_pool'] = target_participant['combat_pool'].to_i - defense_dice if defense_dice > 0
      target_participant['mana'] = target_participant['mana'].to_i - target_mana_cost if target_mana_cost > 0

      temp_hp = target_participant['temporary_hit_points'].to_i
      absorbed_major = [major, temp_hp].min; temp_hp -= absorbed_major
      absorbed_moderate = [moderate, temp_hp].min; temp_hp -= absorbed_moderate
      absorbed_minor = [minor, temp_hp].min; temp_hp -= absorbed_minor
      target_participant['temporary_hit_points'] = temp_hp
      major -= absorbed_major
      moderate -= absorbed_moderate
      minor -= absorbed_minor

      target_participant['minor_damage'] = target_participant['minor_damage'].to_i + minor
      target_participant['moderate_damage'] = target_participant['moderate_damage'].to_i + moderate
      target_participant['major_damage'] = target_participant['major_damage'].to_i + major

      # Subtract ally dice spent (Shield of Faith blockers, etc.)
      ally_data = params[:ally_data] || ''
      ally_data.split(';').each do |entry|
        next if entry.empty?
        aid, adice = entry.split(':').map(&:to_i)
        ally = combat_data['participants'].find { |p| p['id'] == aid }
        ally['combat_pool'] = ally['combat_pool'].to_i - adice if ally && adice > 0
      end

      # Subtract mana from Healing Word casters
      hw_data = params[:healing_word_data] || ''
      hw_data.split(';').each do |entry|
        next if entry.empty?
        hid, hcost = entry.split(':').map(&:to_i)
        healer = combat_data['participants'].find { |p| p['id'] == hid }
        healer['mana'] = healer['mana'].to_i - hcost if healer && hcost > 0
      end

      Tools.save_json('combat.json', combat_data)

      total = minor + moderate + major
      absorbed = absorbed_major + absorbed_moderate + absorbed_minor
      target_name = CharacterSheet.new(
        Tools.load_json('characters.json').find { |c| c['id'] == (target_participant['char_id'] || target_participant['id']) }
      ).name
      if total > 0 || absorbed > 0
        suffix = absorbed > 0 ? " (#{absorbed} absorbed by temp HP)" : ""
        Combat.add_log("#{character.name}'s Spiritual Weapon attacks #{target_name}: #{total} damage (#{minor}/#{moderate}/#{major})#{suffix}")
      else
        Combat.add_log("#{character.name}'s Spiritual Weapon attacks #{target_name} - missed")
      end

    else
      # Generic concentrate reapply: the caster continues to focus on the
      # spell. No mana cost. Log it as a concentrate action.
      target_names = (effect['target_names'] || []).dup
      if new_target_ids.any?
        target_names = target_names_for.call(new_target_ids)
      end
      suffix = target_names.empty? ? "" : " on #{target_names.join(', ')}"
      Combat.add_log("#{character.name} concentrates on #{spell_name}#{suffix}")
    end

  elsif action == 'dismiss_effect'
    effect_index = params[:effect_index].to_i
    combat_data['active_effects'] ||= []
    removed = combat_data['active_effects'].delete_at(effect_index)
    Tools.save_json('combat.json', combat_data)
    Combat.add_log("#{removed['spell_name']} ended") if removed

  elsif action == 'end_turn'
    participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    char_id = participant['char_id'] || participant['id']
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    Combat.add_log("#{character.name} ends turn")
    Combat.advance_turn

  elsif action == 'start_of_turn'
    participant = combat_data['participants'].find { |p| p['id'] == combat_id }
    halt 400, "Participant not found" unless participant
    char_id = participant['char_id'] || participant['id']
    character_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
    character = CharacterSheet.new(character_data)

    log_lines = ["#{character.name} starts turn"]

    campaign = Tools.load_json('campaign.json')
    campaign = {} unless campaign.is_a?(Hash)
    rounds_elapsed = campaign['rounds_elapsed'].to_i

    # Step 1: purge active_effects targeting this combatant whose end round
    # has arrived. Effects with no ends_on_round (e.g. concentration spells)
    # are untouched. ends_on_round is set when the effect is created, as
    # rounds_elapsed_at_creation + duration, so the effect clears the first
    # time the target hits Start of Turn on or after that round.
    # Wards additionally roll back whatever temp HP they contributed so
    # the shielding disappears with the spell.
    combat_data['active_effects'] ||= []
    combat_data['active_effects'].reject! do |effect|
      next false unless effect['ends_on_round']
      target_ids = effect['target_combat_ids'] || []
      next false unless target_ids.include?(combat_id)
      if effect['ends_on_round'].to_i <= rounds_elapsed
        if effect['temp_hp_added'].to_i > 0
          before_temp = participant['temporary_hit_points'].to_i
          participant['temporary_hit_points'] = [before_temp - effect['temp_hp_added'].to_i, 0].max
          log_lines << "  #{effect['spell_name']} ends on #{character.name} (temp HP #{before_temp} -> #{participant['temporary_hit_points']})"
        else
          log_lines << "  #{effect['spell_name']} ends on #{character.name}"
        end
        true
      else
        false
      end
    end

    # Step 2: resolve each active condition in insertion order. The client
    # submits save results as `successes_<name>` (integer) for each.
    participant['conditions'] ||= {}
    participant['condition_meta'] ||= {}
    participant['conditions'].keys.each do |cname|
      value = participant['conditions'][cname].to_i
      next if value <= 0
      successes_param = params["successes_#{cname}".to_sym] || params["successes_#{cname}"]
      successes = successes_param.to_i

      case cname
      when 'bleed'
        # 1 point + 1 per 10 severity, reduced by 1 per success, min 0.
        raw_damage = 1 + (value / 10)
        dealt = [raw_damage - successes, 0].max
        if dealt > 0
          temp_hp = participant['temporary_hit_points'].to_i
          absorbed = [dealt, temp_hp].min
          participant['temporary_hit_points'] = temp_hp - absorbed
          remaining = dealt - absorbed
          if remaining > 0
            participant['minor_damage'] = participant['minor_damage'].to_i + remaining
          end
          absorb_suffix = absorbed > 0 ? " (#{absorbed} absorbed by temp HP)" : ""
          log_lines << "  Bleed save (#{successes} successes): #{dealt} minor damage#{absorb_suffix}"
        else
          log_lines << "  Bleed save (#{successes} successes): no damage"
        end
      when 'ghoul_paralysis'
        # Paralysis rounds mirrors the bleed formula:
        # rounds = (1 + severity/10) - successes, floor 0. If any rounds
        # result, set ends_on_round = rounds_elapsed + rounds so the
        # effect clears at the target's Start of Turn `rounds` rounds from
        # now. Stack by pushing the existing effect's end back by `rounds`.
        raw_rounds = 1 + (value / 10)
        rounds = [raw_rounds - successes, 0].max
        if rounds > 0
          existing = combat_data['active_effects'].find do |e|
            e['spell_name'] == 'Paralyzed' && (e['target_combat_ids'] || []).include?(combat_id)
          end
          if existing
            new_end = existing['ends_on_round'].to_i + rounds
            existing['ends_on_round'] = new_end
            log_lines << "  Ghoul paralysis save (#{successes} successes): +#{rounds} paralysis round#{'s' unless rounds == 1} (now ends R#{new_end})"
          else
            end_round = rounds_elapsed + rounds
            combat_data['active_effects'] << {
              'caster_id' => nil,
              'caster_name' => 'Ghoul Paralysis',
              'spell_name' => 'Paralyzed',
              'target_combat_ids' => [combat_id],
              'target_names' => [character.name],
              'round_cast' => combat_data['round'],
              'ends_on_round' => end_round
            }
            log_lines << "  Ghoul paralysis save (#{successes} successes): PARALYZED until R#{end_round} (#{rounds} round#{'s' unless rounds == 1})"
          end
        else
          log_lines << "  Ghoul paralysis save (#{successes} successes): no paralysis (#{raw_rounds} blocked)"
        end
      when 'minor_strength_poison'
        # (1 + severity/10) minor STR damage, reduced by 1 per success,
        # min 0. Accumulates on participant.ability_damage.str.minor and
        # persists until cured (e.g. by Restoration).
        raw_damage = 1 + (value / 10)
        dealt = [raw_damage - successes, 0].max
        if dealt > 0
          participant['ability_damage'] ||= {}
          participant['ability_damage']['str'] ||= {}
          participant['ability_damage']['str']['minor'] =
            participant['ability_damage']['str']['minor'].to_i + dealt
          log_lines << "  Minor strength poison save (#{successes} successes): #{dealt} minor STR damage"
        else
          log_lines << "  Minor strength poison save (#{successes} successes): no damage (#{raw_damage} blocked)"
        end
      else
        log_lines << "  #{cname.tr('_', ' ').capitalize} save (#{successes} successes)"
      end

      # Universal decay: reduce severity by 1 + successes, floor 0.
      new_value = [value - (1 + successes), 0].max
      if new_value <= 0
        participant['conditions'].delete(cname)
        # Clear any meta tied to this condition ending.
        if cname == 'ghoul_paralysis'
          participant['condition_meta'].delete('max_ghoul_tier')
        end
        log_lines << "  #{cname.tr('_', ' ').capitalize} ends"
      else
        participant['conditions'][cname] = new_value
      end
    end

    # Refill combat pool at the start of this combatant's turn. Paralysis
    # and other conditions still apply to whether they can act; the pool
    # just resets to its maximum so they have dice to work with either way.
    pool_before = participant['combat_pool'].to_i
    pool_max = character.combat_pool
    if pool_max != pool_before
      participant['combat_pool'] = pool_max
      log_lines << "  Combat pool refilled: #{pool_before} -> #{pool_max}"
    end

    Tools.save_json('combat.json', combat_data)
    log_lines.each { |line| Combat.add_log(line) }

  end

  redirect '/combat'
end

post '/combat/reroll_init' do
  redirect '/character/0' unless local_request?
  combat = Combat.new()
  combat.reroll_init
  redirect '/combat'
end

# Clear initiative rolls, reset the displayed round counter, and drop
# any round-bound active effects (they reference absolute round numbers
# that stop making sense after the reset). Leaves participants and their
# HP / damage / mana in place, so reopening combat just needs a reroll.
post '/combat/end_combat' do
  redirect '/character/0' unless local_request?
  combat_data = Tools.load_json('combat.json')
  combat_data['active'] = false
  combat_data['round'] = 0
  combat_data['current_turn'] = 0
  combat_data['current_turn_id'] = 0
  combat_data['active_effects'] = []
  (combat_data['participants'] || []).each { |p| p['initiative'] = '' }
  Tools.save_json('combat.json', combat_data)

  campaign = Tools.load_json('campaign.json')
  campaign = {} unless campaign.is_a?(Hash)
  campaign['rounds_elapsed'] = 0
  Tools.save_json('campaign.json', campaign)

  redirect '/combat'
end

post '/combat/set_turn/:id' do
  redirect '/character/0' unless local_request?
  Combat.set_current_turn(params[:id].to_i)
  redirect '/combat'
end

# Roll initiative for just one combatant (e.g. a newcomer joining mid-fight).
# The full reroll_init button still rerolls everyone; this avoids scrambling
# the order for combatants who have already rolled.
post '/combat/roll_init/:id' do
  redirect '/character/0' unless local_request?
  Combat.new.reroll_init_for(params[:id].to_i)
  redirect '/combat'
end

get '/' do
  redirect '/character/0'
end

get '/character/:index' do
  character_list = Tools.load_json('characters.json').select { |character| character["group"] == "PC" }
  load_character_view(character_list, params[:index].to_i, '/character')
end

get '/enemies/:index' do
  redirect '/character/0' unless local_request?
  templates = Templates.creatures
  halt 404, "No enemy templates found" if templates.empty?

  index = params[:index].to_i % templates.length
  @total_characters = templates.length
  @prev_index = (index - 1) % templates.length
  @next_index = (index + 1) % templates.length
  @current_index = index
  @route_prefix = '/enemies'

  template = templates[index]
  @template = template
  @character = get_info(Templates.preview_character(template))
  @compendium = Compendium.new
  @enemy_list = templates.each_with_index.map { |t, i| { index: i, id: t['id'], name: t['name'], source: t['_source'] || 'General' } }
  @enemy_groups = Templates.creatures_grouped.map do |label, group_creatures|
    group_ids = group_creatures.map { |c| c['id'].to_s }.to_set
    { label: label, enemies: @enemy_list.select { |e| group_ids.include?(e[:id].to_s) } }
  end

  combat_data = Tools.load_json('combat.json')
  @combat_participants = combat_data['participants']
  characters = Tools.load_json('characters.json')
  @template_instances = characters.select { |c| c['template_id'].to_s == template['id'].to_s }
  @all_characters = characters

  erb :enemies
end

post '/combat/add_enemy' do
  redirect '/character/0' unless local_request?
  template_id = params[:enemy_id].to_s
  template = Templates.find(template_id)
  halt 400, "Enemy template not found" unless template

  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')

  # Pick a fresh integer id above any existing character record and any
  # char_id in combat (stale combat rows from before the refactor can
  # reference enemy ids that were pulled out of characters.json).
  char_ids = characters.map { |c| c['id'].to_i }
  combat_refs = combat_data['participants'].map { |p| (p['char_id'] || p['id']).to_i }
  new_id = ([0] + char_ids + combat_refs).max + 1

  instance = Templates.instantiate(template_id, new_id: new_id)
  instance['template_id'] = template_id
  characters << instance
  Tools.save_json('characters.json', characters)

  max_participant_id = combat_data['participants'].map { |p| p['id'].to_i }.max || 0
  combat_id = max_participant_id + 1

  character = CharacterSheet.new(instance)
  combat_data['participants'] << {
    'id' => combat_id,
    'char_id' => new_id,
    'initiative' => '',
    'mana' => character.mana_max,
    'combat_pool' => character.combat_pool,
    'saturation' => 0,
    'minor_damage' => 0,
    'moderate_damage' => 0,
    'major_damage' => 0,
    'temporary_hit_points' => 0
  }
  Tools.save_json('combat.json', combat_data)
  redirect back
end

get '/enemies/instance/:id' do
  redirect '/character/0' unless local_request?
  char_id = params[:id].to_i
  characters = Tools.load_json('characters.json')
  instance = characters.find { |c| c['id'] == char_id }
  halt 404, "Enemy instance not found" unless instance

  @character = get_info(instance)
  @compendium = Compendium.new
  @instance_data = instance

  combat_data = Tools.load_json('combat.json')
  @combat_participants = combat_data['participants']
  templates = Templates.creatures
  @enemy_list = templates.each_with_index.map { |t, i| { index: i, id: t['id'], name: t['name'], source: t['_source'] || 'General' } }
  @enemy_groups = Templates.creatures_grouped.map do |label, group_creatures|
    group_ids = group_creatures.map { |c| c['id'].to_s }.to_set
    { label: label, enemies: @enemy_list.select { |e| group_ids.include?(e[:id].to_s) } }
  end

  @all_characters = characters

  erb :enemy_instance
end

post '/enemies/instance/:id/rename' do
  redirect '/character/0' unless local_request?
  char_id = params[:id].to_i
  new_name = params[:name].to_s.strip
  halt 400, "Name cannot be blank" if new_name.empty?

  characters = Tools.load_json('characters.json')
  instance = characters.find { |c| c['id'] == char_id }
  halt 404, "Enemy instance not found" unless instance

  instance['name'] = new_name
  Tools.save_json('characters.json', characters)
  redirect "/enemies/instance/#{char_id}"
end

post '/enemies/instance/:id/reroll' do
  redirect '/character/0' unless local_request?
  char_id = params[:id].to_i
  characters = Tools.load_json('characters.json')
  old_instance = characters.find { |c| c['id'] == char_id }
  halt 404, "Enemy instance not found" unless old_instance
  template_id = old_instance['template_id']
  halt 400, "Instance has no template_id" unless template_id

  new_instance = Templates.instantiate(template_id, new_id: char_id)
  new_instance['template_id'] = template_id
  idx = characters.index { |c| c['id'] == char_id }
  characters[idx] = new_instance

  # Update the combat participant so mana/combat_pool reflect new stats.
  combat_data = Tools.load_json('combat.json')
  participant = combat_data['participants'].find { |p| p['char_id'] == char_id }
  if participant
    cs = CharacterSheet.new(new_instance)
    participant['mana'] = cs.mana_max
    participant['combat_pool'] = cs.combat_pool
    participant['minor_damage'] = 0
    participant['moderate_damage'] = 0
    participant['major_damage'] = 0
    participant['temporary_hit_points'] = 0
    participant['saturation'] = 0
    participant['initiative'] = ''
    Tools.save_json('combat.json', combat_data)
  end

  Tools.save_json('characters.json', characters)
  redirect "/enemies/instance/#{char_id}"
end

post '/combat/remove_enemy' do
  redirect '/character/0' unless local_request?
  combat_id = params[:combat_id].to_i
  combat_data = Tools.load_json('combat.json')
  combat_data['participants'].reject! { |p| p['id'] == combat_id }
  Tools.save_json('combat.json', combat_data)
  redirect back
end

post '/combat/clear_enemies' do
  redirect '/character/0' unless local_request?
  characters = Tools.load_json('characters.json')
  pc_ids = characters.select { |c| c['group'] == 'PC' }.map { |c| c['id'] }
  combat_data = Tools.load_json('combat.json')
  combat_data['participants'].select! { |p| pc_ids.include?(p['char_id'] || p['id']) }
  Tools.save_json('combat.json', combat_data)
  redirect back
end

post '/add_note' do
  characters = Tools.load_json('characters.json')
  notes = Tools.load_json('notes.json')

  char_id = params[:owner_id].to_i
  notes << {
    "owner_id" => char_id,
    "note" => params[:note],
    "public" => false,
    "type" => "note"
  }

  Tools.save_json('notes.json', notes)
  char_index = characters.find_index { |char| char['id'].to_i == char_id.to_i }

  redirect "/character/#{char_index}"
end

get '/add_item' do
  redirect '/character/0' unless local_request?
  @characters = Tools.load_json('characters.json')
  @item_tree = Tools.load_json('rules.json')['reference']['item_tree']
  erb :add_item
end

post '/add_item' do
  redirect '/character/0' unless local_request?

  items = Tools.load_json('equipment.json')

  # Build the new item from form params. item_id is not persisted -- it's
  # synthesized from the array position at load time.
  new_item = {
    "owner_id" => params[:owner_id].to_i,
    "name" => params[:name],
    "type" => params[:type],
    "subtype" => params[:subtype],
    "bonus" => params[:bonus].to_i,
    "properties" => {}
  }

  # Add optional fields
  new_item["quantity"] = params[:quantity].to_i if params[:quantity] && !params[:quantity].empty?
  new_item["description"] = params[:description] if params[:description] && !params[:description].empty?
  new_item["equipped"] = params[:equipped] == "true"

  items << new_item
  Tools.save_json('equipment.json', items)

  redirect '/add_item'
end

get '/notes/:viewer_id' do
  viewer_id = params[:viewer_id].to_i

  # Redirect if not local and trying to view DM notes
  redirect '/notes/1' if viewer_id == 0 && !@is_local

  @viewer_id = viewer_id
  @is_dm = viewer_id == 0 && @is_local
  @notes = Tools.load_json('notes.json')
  @characters = Tools.load_json('characters.json')
  @current_chapter = params[:chapter] ? params[:chapter].to_i : nil

  erb :notes_view
end

post '/add_note_entry' do
  notes = Tools.load_json('notes.json')

  new_note = {
    "owner_id" => params[:owner_id].to_i,
    "note" => params[:note],
    "public" => params[:public] == "true"
  }

  new_note["type"] = params[:type] if params[:type] && !params[:type].empty?
  new_note["title"] = params[:title] if params[:title] && !params[:title].empty?
  new_note["tier"] = params[:tier].to_i if params[:tier] && !params[:tier].empty?
  new_note["chapter"] = params[:chapter].to_i if params[:chapter] && !params[:chapter].empty?
  new_note["active"] = true if params[:active] == "true"

  notes << new_note
  Tools.save_json('notes.json', notes)

  redirect "/notes/#{params[:owner_id]}"
end

get '/spells' do
  compendium = Compendium.new
  @spells = compendium.data["spells"].sort_by { |name, _| name.downcase }.to_h
  @spell_schools = compendium.data["spell_schools"] || {}
  @spell_schools = @spell_schools.map { |s| [s, ""] }.to_h if @spell_schools.is_a?(Array)
  @range_labels = compendium.data["range"]
  @all_skills = @spells.values.flat_map { |s| s["skill"] || [] }.uniq.sort
  erb :spell_list
end

get '/spell/:name' do
  compendium = Compendium.new
  @spell_name = params[:name]
  @spell = compendium.data["spells"][@spell_name]
  @tier_index = nil

  unless @spell
    compendium.data["spells"].each do |base_name, spell_data|
      tiers = spell_data["tier"].is_a?(Array) ? spell_data["tier"] : [spell_data["tier"]]
      tiers.each_with_index do |tier_val, idx|
        variant_names = []
        variant_names << "#{spell_data["prefix"][idx]} #{base_name}" if spell_data["prefix"] && spell_data["prefix"][idx]
        variant_names << "#{base_name} #{spell_data["suffix"][idx]}" if spell_data["suffix"] && spell_data["suffix"][idx]
        if variant_names.any? { |v| v == @spell_name }
          @spell = spell_data
          @spell_name = base_name
          @tier_index = idx
          break
        end
      end
      break if @spell
    end
  end

  halt 404, "Spell not found" unless @spell
  @school = @spell["school"] || "universal"
  @range_labels = compendium.data["range"]
  erb :spell_detail
end

post '/spells/add' do
  redirect '/spells' unless local_request?
  compendium_data = Tools.load_json('compendium.json')

  tiers = params[:tiers].split(',').map(&:strip).map(&:to_i)
  tiers = tiers.length == 1 ? tiers.first : tiers

  save_val = params[:save] == "0" ? 0 : params[:save]
  skills = params[:skills].to_s.split(',').map(&:strip).reject(&:empty?)
  items = params[:items].to_s.split(',').map(&:strip).reject(&:empty?)

  compendium_data["spells"][params[:name]] = {
    "tier" => tiers,
    "save" => save_val,
    "school" => params[:school] || "universal",
    "items" => items.empty? ? [] : items,
    "range" => params[:range].to_i,
    "duration" => params[:duration] || "instant",
    "casting_time" => params[:casting_time].to_f,
    "skill" => skills,
    "properties" => [],
    "effect_hash" => {},
    "description" => params[:description]
  }

  Tools.save_json('compendium.json', compendium_data)
  redirect '/spells'
end

get '/store' do
  @store_items = Tools.load_json('store.json')
  @campaign = Tools.load_json('campaign.json')
  @characters = Tools.load_json('characters.json')
  compendium = Compendium.new
  @spell_items = compendium.spell_store_items
  @ammo_items = compendium.ammunition_store_items
  @ritual_items = compendium.ritual_store_items
  @spell_data = compendium.data["spells"]
  @item_costs = compendium.data["item_costs"]
  @property_costs = compendium.data["property_costs"] || {}
  # rules.reference tables referenced by store variants (e.g. bag_of_holding
  # sizes) are passed to the view so description templates like "{weight}
  # pounds / {capacity} pounds / {volume} cubic feet" resolve client-side.
  @rules_reference = Tools.load_json('rules.json')['reference'] || {}
  # Known-ritual map keyed by char id, used by the store to flag rituals a
  # PC already has in their spellbook (so a re-purchase can't accidentally be
  # submitted).
  @character_rituals = {}
  @characters.each do |c|
    list = (c['rituals'] || []).flatten.map(&:to_s)
    @character_rituals[c['id']] = list
  end
  erb :store
end

post '/purchase_ritual' do
  compendium = Compendium.new
  campaign = Tools.load_json('campaign.json')
  characters = Tools.load_json('characters.json')

  variant_name = params[:spell_name].to_s
  owner_id = params[:owner_id].to_i
  ritual = compendium.ritual_store_items.find { |r| r['name'] == variant_name }
  halt 400, "Ritual not found" unless ritual

  owner = characters.find { |c| c['id'] == owner_id }
  halt 400, "Owner not found" unless owner

  owner['rituals'] ||= []
  flat_existing = owner['rituals'].flatten.map(&:to_s)
  if flat_existing.include?(variant_name)
    redirect '/store?error=already_known'
    return
  end
  if campaign['gold'].to_i < ritual['price'].to_i
    redirect '/store?error=insufficient_gold'
    return
  end

  # Append to the tier bucket matching the ritual's spell tier; create the
  # bucket (and any missing earlier buckets) if needed.
  tier = ritual['tier'].to_i
  owner['rituals'][tier] ||= []
  while owner['rituals'].length <= tier
    owner['rituals'] << []
  end
  owner['rituals'][tier] << variant_name
  campaign['gold'] = campaign['gold'].to_i - ritual['price'].to_i
  Tools.save_json('characters.json', characters)
  Tools.save_json('campaign.json', campaign)
  redirect '/store?success=true'
end

post '/purchase/:item_index' do
  store_items = Tools.load_json('store.json')
  campaign = Tools.load_json('campaign.json')
  items = Tools.load_json('equipment.json')

  compendium = Compendium.new
  if params[:item_index] == 'ammo_lookup'
    store_item = compendium.ammunition_store_items.find do |item|
      item['tier'] == params[:tier].to_i &&
      (params[:property].to_s.empty? ? !item['properties'].keys.any? { |k| k != 'consumable' } :
        item['properties'][params[:property].downcase] == true)
    end
    halt 400, "Ammunition not found" unless store_item
  elsif params[:item_index] == 'spell_lookup'
    store_item = compendium.spell_store_items.find do |item|
      item['spell'] == params[:spell_name] &&
      item['subtype'] == params[:item_type] &&
      item['tier'] == params[:tier].to_i
    end
    halt 400, "Spell item not found" unless store_item
  elsif params[:item_index].start_with?('spell_')
    spell_index = params[:item_index].sub('spell_', '').to_i
    store_item = compendium.spell_store_items[spell_index]
  elsif params[:item_index].start_with?('ammo_')
    ammo_index = params[:item_index].sub('ammo_', '').to_i
    store_item = compendium.ammunition_store_items[ammo_index]
  else
    store_item = store_items[params[:item_index].to_i]
  end

  # Resolve variants: if the store entry has a `variants` array, the client
  # submits `variant_index` to pick one. The variant contributes its own
  # display_name, price, and bonus; the description is rendered from the
  # parent's template, substituting any {placeholders} from the linked
  # rules.reference table (e.g. bag_of_holding sizes) so weight/capacity/
  # volume numbers remain the single source of truth.
  variant = nil
  if store_item['variants']
    idx = params[:variant_index].to_i
    variant = store_item['variants'][idx]
    halt 400, "Variant not found" unless variant
  end

  purchase_name  = variant ? variant['display_name'] : store_item['name']
  purchase_price = variant ? variant['price']        : store_item['price']
  purchase_bonus = variant ? variant['bonus']        : store_item['bonus']
  purchase_props = (store_item['properties'] || {}).dup

  # properties_template resolves {placeholder} fields using values from the
  # selected variant. Cloak/Belt/Headband use this to synthesize the
  # properties.enhancement block so worn items feed into the character's
  # attribute/save enhancement pool without enumerating full properties for
  # every variant row.
  if variant && store_item['properties_template']
    resolved_template = resolve_properties_template(store_item['properties_template'], variant)
    purchase_props = purchase_props.merge(resolved_template)
  end

  purchase_desc = store_item['description']
  if variant && store_item['variant_rules_table'] && purchase_desc
    table = Tools.load_json('rules.json').dig('reference', store_item['variant_rules_table']) || {}
    ref   = table[variant['rules_key']] || {}
    purchase_desc = purchase_desc.gsub(/\{(\w+)\}/) { |m| ref[$1].nil? ? m : ref[$1].to_s }
  end

  # Build the purchase list: owner_id -> quantity. Scrolls/potions/oils submit a
  # quantities hash (one entry per PC); everything else submits a single owner_id.
  purchases = if params[:quantities].is_a?(Hash)
    params[:quantities].each_with_object({}) do |(oid, qty), acc|
      q = qty.to_i
      acc[oid.to_i] = q if q > 0
    end
  else
    oid = params[:owner_id].to_i
    oid > 0 ? { oid => 1 } : {}
  end

  if purchases.empty?
    redirect '/store?error=insufficient_gold'
    return
  end

  total_qty = purchases.values.sum
  total_cost = purchase_price * total_qty

  if campaign['gold'] < total_cost
    redirect '/store?error=insufficient_gold'
    return
  end

  purchases.each do |owner_id, qty|
    existing_item = items.find do |i|
      i['owner_id'] == owner_id &&
      i['name'] == purchase_name &&
      i['type'] == store_item['type'] &&
      i['subtype'] == store_item['subtype']
    end

    if existing_item
      existing_item['quantity'] = (existing_item['quantity'] || 1) + qty
    else
      bonus = purchase_bonus
      if store_item['tier'] && %w[potion oil scroll].include?(store_item['subtype'])
        bonus = store_item['tier']
      end
      new_item = {
        'owner_id' => owner_id,
        'name' => purchase_name,
        'type' => store_item['type'],
        'subtype' => store_item['subtype'],
        'bonus' => bonus,
        'properties' => purchase_props
      }
      new_item['equipped'] = false unless store_item['type'] == 'tattoo'
      new_item['description'] = purchase_desc if purchase_desc
      new_item['quantity'] = qty if purchase_props['consumable']
      items << new_item
    end
  end

  campaign['gold'] -= total_cost

  Tools.save_json('equipment.json', items)
  Tools.save_json('campaign.json', campaign)

  redirect '/store?success=true'
end

# --- Downtime ---------------------------------------------------------------

# Locate (or create) the combat.json participant record for a PC. Downtime
# reads and writes the same per-character state used during combat so the
# current HP / mana / saturation stays consistent across screens.
def downtime_find_or_create_participant(combat_data, character)
  char_id = character.id
  participant = (combat_data['participants'] ||= []).find { |p| (p['char_id'] || p['id']) == char_id }
  return participant if participant
  max_id = combat_data['participants'].map { |p| p['id'].to_i }.max || 0
  participant = {
    'id' => [max_id + 1, char_id].max,
    'char_id' => char_id,
    'initiative' => '',
    'mana' => character.mana_max,
    'combat_pool' => character.combat_pool,
    'saturation' => 0,
    'minor_damage' => 0,
    'moderate_damage' => 0,
    'major_damage' => 0,
    'temporary_hit_points' => 0
  }
  combat_data['participants'] << participant
  participant
end

# Flattened list of spell variants a character knows that resolve to a given
# base spell (e.g., "Cure" -> ["Cure Lesser Wounds", ...]).
def downtime_known_variants(character, compendium, base_name)
  (character.spell_list || []).flatten.select do |spell_name|
    resolved = compendium.resolve_spell_variant(spell_name)
    resolved && resolved[0] == base_name
  end
end

get '/downtime' do
  characters = Tools.load_json('characters.json')
  @campaign = Tools.load_json('campaign.json')
  @compendium = Compendium.new
  @pcs = characters.select { |c| c['group'] == 'PC' }.map { |c| CharacterSheet.new(c) }
  @services = @compendium.data['spellcasting_services'] || []

  # Per-PC rows: who can cast Cure or Recharge, who can cast Surgery, and
  # what healing consumables they own. Cure + Recharge share the Cast form
  # since they both target an ally and consume caster mana.
  # Cast Spell now folds Surgery + Restoration in alongside Cure / Recharge.
  cast_bases = %w[Cure Recharge Restoration Standard\ Surgery]
  @cast_casters = @pcs.select do |pc|
    cast_bases.any? { |b| downtime_known_variants(pc, @compendium, b).any? }
  end
  # Surgery still needs its own list for the urgent-actions UI (which lists
  # Surgery save dice/TN per caster).
  @surgery_casters = @pcs.select { |pc| downtime_known_variants(pc, @compendium, 'Standard Surgery').any? }

  # Rituals with downtime-mechanical effect (Cure/Recharge). We only surface
  # these in the Cast Ritual cell -- utility rituals (Invisibility, Disguise,
  # etc.) stay in the character's ritual list on the sheet but aren't
  # castable through this UI.
  ritual_bases = %w[Cure Recharge Restoration Standard\ Surgery]
  @ritual_casters = @pcs.select do |pc|
    (pc.ritual_list || []).flatten.compact.any? do |r|
      resolved = @compendium.resolve_spell_variant(r)
      resolved && ritual_bases.include?(resolved[0])
    end
  end

  # Consumable owner map: char_id -> [items]. Restricted to Cure/Recharge
  # potions and scrolls, plus Standard Surgery scrolls, per the downtime spec.
  @consumable_owners = {}
  @pcs.each do |pc|
    items = pc.item_list.select do |i|
      effect = @compendium.item_effects(i)
      next false unless effect
      effect[:type] == :cure || effect[:type] == :mana || effect[:base_name] == 'Standard Surgery'
    end
    @consumable_owners[pc.id] = items unless items.empty?
  end

  # --- DT_DATA: single JSON payload driving all client-side previews. ---
  rules = Tools.load_json('rules.json')
  heal_rate = rules['advancement']['natural']['heal_rate']
  dice_rules = rules['dice'] || {}
  base_tn = dice_rules['base_target_number'].to_i
  tn_min = dice_rules['tn_minimum'].to_i
  tn_max = dice_rules['tn_maximum'].to_i

  pc_payload = {}
  pc_order = []
  combat_data_now = Tools.load_json('combat.json')
  ability_heal_rate = rules.dig('advancement', 'natural', 'ability_heal_rate') || heal_rate
  @pcs.each do |pc|
    pc_order << pc.id
    row_base = pc.tier * 3
    rows = [heal_rate[row_base], heal_rate[row_base + 1], heal_rate[row_base + 2]]
    ability_rows = [ability_heal_rate[row_base], ability_heal_rate[row_base + 1], ability_heal_rate[row_base + 2]]

    # Total queued ability damage points by severity, plus the FIFO queue
    # itself so the preview can surface what's about to heal.
    participant = (combat_data_now['participants'] || []).find { |p| (p['char_id'] || p['id']) == pc.id }
    ad = participant ? (participant['ability_damage'] || {}) : {}
    ability_totals = { 'minor' => 0, 'moderate' => 0, 'major' => 0 }
    ability_queue = []
    ad.each do |attr, sevs|
      next unless sevs.is_a?(Hash)
      %w[major moderate minor].each do |sev|
        n = sevs[sev].to_i
        next if n <= 0
        ability_totals[sev] = ability_totals[sev].to_i + n
      end
      sevs.each { |sev, n| ability_queue << [attr, sev, n.to_i] if n.to_i > 0 }
    end

    pc_payload[pc.id.to_s] = {
      id: pc.id,
      name: pc.name,
      tier: pc.tier,
      cha: pc.cha,
      hpMax: pc.hp_max,
      mana: pc.current_mana,
      manaMax: pc.mana_max,
      saturation: pc.saturation,
      damage: [pc.minor_damage, pc.moderate_damage, pc.major_damage],
      abilityDamage: { minor: ability_totals['minor'], moderate: ability_totals['moderate'], major: ability_totals['major'] },
      abilityQueue: ability_queue,
      tempHp: pc.temporary_hit_points,
      improvedHealing: pc.ability_list.include?('improved_healing'),
      rows: rows,
      abilityRows: ability_rows
    }
  end

  # Castable spells (Cure + Recharge variants) keyed by variant name,
  # including which PCs know each one and the resolved spell effect +
  # spell tier / mana cost so the client preview can simulate the cast.
  # Build a per-spell entry for the Cast Spell / Cast Ritual dropdown. Returns
  # nil when the variant doesn't resolve to one of the supported effect types.
  cast_entry_for = lambda do |variant|
    resolved = @compendium.resolve_spell_variant(variant)
    next nil unless resolved
    base_name = resolved[0]
    cure = @compendium.cure_effects(variant)
    mana = (cure.nil?) ? @compendium.mana_effects(variant) : nil
    ability = (cure.nil? && mana.nil?) ? @compendium.ability_cure_effects(variant) : nil
    type = cure ? 'cure' : (mana ? 'mana' : (ability ? 'ability' : (base_name == 'Standard Surgery' ? 'surgery' : nil)))
    next nil unless type
    base = cure || mana || ability
    tier_val = (base ? base[:tier_val] : (resolved[3])).to_i
    mana_cost = tier_val == 0 ? 1 : (tier_val * 2 + 2)
    entry = {
      type: type,
      baseName: base_name,
      tier: tier_val,
      manaCost: mana_cost,
      saturation: base ? base[:saturation] : nil,
      minimumSaturation: base ? base[:minimum_saturation] : nil
    }
    case type
    when 'cure', 'ability'
      entry[:minor] = base[:minor]; entry[:moderate] = base[:moderate]; entry[:major] = base[:major]
    when 'mana'
      entry[:mana] = base[:mana]
    when 'surgery'
      # Surgery has no pool: it heals N major (where N = successes rolled),
      # adds 2 * pre-cast major as moderate damage, and triggers off the
      # caster's healing skill check. Saturation is computed inline (10 per
      # cured major, min 5 per cured major).
    end
    entry
  end

  cast_payload = {}
  @cast_casters.each do |caster|
    cast_bases.each do |base|
      downtime_known_variants(caster, @compendium, base).each do |variant|
        entry = cast_entry_for.call(variant)
        next unless entry
        cast_payload[variant] ||= entry.merge(casterIds: [])
        cast_payload[variant][:casterIds] << caster.id
      end
    end
  end
  cast_payload.each_value { |v| v[:casterIds].uniq! }

  # Ritual casting payload: same shape as cast_payload but driven by each
  # PC's ritual_list filtered to Cure / Recharge / Restoration / Surgery
  # variants. Also carries the per-tier gold cost so the preview can show it.
  ritual_gold_cost_by_tier = @compendium.data['ritual_gold_cost_by_tier'] || [1, 10, 50, 100, 200, 400]
  ritual_cast_payload = {}
  @ritual_casters.each do |caster|
    (caster.ritual_list || []).flatten.compact.each do |variant|
      resolved = @compendium.resolve_spell_variant(variant)
      next unless resolved && ritual_bases.include?(resolved[0])
      entry = cast_entry_for.call(variant)
      next unless entry
      gold_cost = ritual_gold_cost_by_tier[entry[:tier]] || ritual_gold_cost_by_tier.last
      ritual_cast_payload[variant] ||= entry.merge(goldCost: gold_cost, casterIds: [])
      ritual_cast_payload[variant][:casterIds] << caster.id
    end
  end
  ritual_cast_payload.each_value { |v| v[:casterIds].uniq! }

  # Surgery casters with dice / TN computed from their healing skill.
  surgery_payload = {}
  @surgery_casters.each do |caster|
    dice = caster.skill_dice(:healing)
    bonus = caster.skill_bonus(:healing)
    raw_tn = base_tn - bonus
    tn = [tn_min, [raw_tn, tn_max].min].max
    starting_successes = raw_tn < tn_min ? (tn_min - raw_tn) : 0
    surgery_payload[caster.id.to_s] = {
      id: caster.id,
      name: caster.name,
      dice: dice,
      tn: tn,
      startingSuccesses: starting_successes,
      improvedHealing: caster.ability_list.include?('improved_healing'),
      tier: caster.tier
    }
  end

  # Services grouped by spell. Each entry has the resolved effect (cure OR
  # mana-restoration for Recharge-style spells) and the improved_healing flag
  # derived from the caster's class.
  services_by_spell = {}
  @services.each do |svc|
    cure_eff = @compendium.cure_effects(svc['spell'])
    mana_eff = cure_eff.nil? ? @compendium.mana_effects(svc['spell']) : nil
    effect = cure_eff || mana_eff
    next unless effect
    type = cure_eff ? 'cure' : 'mana'
    payload_effect = if type == 'cure'
      {
        minor: effect[:minor], moderate: effect[:moderate], major: effect[:major],
        saturation: effect[:saturation], minimumSaturation: effect[:minimum_saturation]
      }
    else
      {
        mana: effect[:mana],
        saturation: effect[:saturation], minimumSaturation: effect[:minimum_saturation]
      }
    end
    services_by_spell[svc['spell']] ||= []
    services_by_spell[svc['spell']] << {
      title: svc['title'],
      casterClass: svc['class'],
      tier: svc['tier'].to_i,
      cost: svc['cost'].to_i,
      # improved_healing reduces saturation for healing spells only; Recharge
      # is Universal school so it never benefits even if the caster has the ability.
      improvedHealing: svc['class'].to_s == 'cleric' && type == 'cure',
      type: type,
      effect: payload_effect
    }
  end

  @dt_data = {
    pcs: pc_payload,
    pcOrder: pc_order,
    castSpells: cast_payload,
    castSpellNames: cast_payload.keys,
    ritualSpells: ritual_cast_payload,
    ritualSpellNames: ritual_cast_payload.keys,
    surgeryCasters: surgery_payload,
    services: services_by_spell,
    servicesSpells: services_by_spell.keys,
    campaignGold: @campaign['gold'].to_i,
    diceRules: { baseTn: base_tn, tnMin: tn_min, tnMax: tn_max }
  }

  # --- Urgent Actions: condition saves + queued heals for every combatant. ---
  # Only rendered in DM view, and only if at least one combatant has an active
  # condition (bleed, ghoul paralysis, etc.).
  @ua_data = nil
  if @is_local
    @ua_data = build_urgent_actions_payload(base_tn, tn_min, tn_max)
  end

  erb :downtime
end

# Build the combatant-list payload used by the Urgent Actions UI. Returns nil
# if there is nothing urgent (no combatant has an active condition).
def build_urgent_actions_payload(base_tn, tn_min, tn_max)
  combat = Combat.new
  return nil if combat.combat_turn_list.empty?

  allowed_bases = (@compendium.data['urgent_action_spells'] || []).map(&:to_s)
  return nil if allowed_bases.empty?

  # Only surface the section when someone has a condition to resolve.
  has_conditions = combat.combat_turn_list.any? { |ct| ct.active_conditions.any? }
  return nil unless has_conditions

  combatants = combat.combat_turn_list.map do |ct|
    char = ct.character
    save_dice = char.save_dice(:con).to_i
    save_bonus_con = char.save_bonus(:con).to_i
    # Base save TN mirrors start_of_turn: start at 9, subtract CON save bonus,
    # then add per-condition modifiers (e.g. highest ghoul tier that hit us).
    base_raw_tn = 9 - save_bonus_con
    max_ghoul_tier = ct.condition_meta['max_ghoul_tier'].to_i

    conditions = ct.active_conditions.map do |cname, value|
      tn_mod = cname == 'ghoul_paralysis' ? max_ghoul_tier : 0
      raw_tn = base_raw_tn + tn_mod
      clamped_tn = [[raw_tn, tn_min].max, tn_max].min
      {
        name: cname,
        label: cname.tr('_', ' ').split.map(&:capitalize).join(' '),
        value: value.to_i,
        dice: save_dice,
        tn: clamped_tn,
        tnModLabel: cname == 'ghoul_paralysis' && tn_mod > 0 ? "ghoul tier +#{tn_mod}" : ''
      }
    end

    # Allowed spells the character knows, flattened across tiers. Each carries
    # its mana cost and whether the character can currently afford it. DM may
    # cast unaffordable spells anyway (marked N/A in the dropdown).
    known_variants = (char.spell_list || []).flatten.select do |spell_name|
      resolved = @compendium.resolve_spell_variant(spell_name)
      resolved && allowed_bases.include?(resolved[0])
    end.uniq

    spells = known_variants.map do |variant|
      resolved = @compendium.resolve_spell_variant(variant)
      base_name, spell_data, _idx, tier_val = resolved
      mana_cost = tier_val.to_i == 0 ? 1 : (tier_val.to_i * 2 + 2)
      affordable = ct.mana.to_i >= mana_cost
      needs_check = base_name == 'Stabilize'
      target_mode = @compendium.target_mode(variant) || 'single'
      kind = base_name == 'Cure' ? 'cure' : (base_name == 'Ward' ? 'ward' : (base_name == 'Stabilize' ? 'stabilize' : 'other'))
      entry = {
        name: variant,
        baseName: base_name,
        tier: tier_val.to_i,
        manaCost: mana_cost,
        affordable: affordable,
        targetMode: target_mode,
        needsCheck: needs_check,
        kind: kind
      }
      if base_name == 'Cure'
        effect = @compendium.cure_effects(variant)
        if effect
          entry[:cure] = {
            minor: effect[:minor], moderate: effect[:moderate], major: effect[:major],
            saturation: effect[:saturation], minimumSaturation: effect[:minimum_saturation]
          }
        end
      elsif base_name == 'Ward'
        ward = @compendium.ward_effects(variant)
        entry[:ward] = { tempHp: ward[:temp_hp] } if ward
      end
      entry
    end

    # Matching consumables (potion/scroll) whose spell resolves to an allowed base.
    items = char.item_list.filter_map do |item|
      fx = @compendium.item_effects(item)
      next nil unless fx
      next nil unless fx[:base_name] && allowed_bases.include?(fx[:base_name].to_s)
      {
        itemId: item['item_id'],
        name: item['name'],
        quantity: item['quantity'] || 1,
        baseName: fx[:base_name],
        kind: fx[:kind].to_s,
        type: fx[:type].to_s,
        targetMode: fx[:target_mode].to_s.empty? ? 'single' : fx[:target_mode].to_s,
        itemTier: fx[:item_tier]
      }
    end

    {
      combatId: ct.combat_id,
      charId: char.id,
      name: combat.display_name(ct),
      group: (char.data['group'] || 'PC'),
      tier: char.tier,
      cha: char.cha,
      mana: ct.mana.to_i,
      manaMax: char.mana_max,
      saturation: ct.saturation.to_i,
      damage: [ct.minor_damage.to_i, ct.moderate_damage.to_i, ct.major_damage.to_i],
      tempHp: ct.temporary_hit_points,
      hpMax: char.hp_max,
      improvedHealing: char.ability_list.include?('improved_healing'),
      conditions: conditions,
      spells: spells,
      items: items
    }
  end

  { combatants: combatants, allowedSpells: allowed_bases, round: combat.combat_turn_list.first ? (Tools.load_json('combat.json')['round'] || 0) : 0 }
end

post '/downtime/cast' do
  compendium = Compendium.new
  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')

  caster_id = params[:caster_id].to_i
  spell_name = params[:spell_name].to_s
  target_id = params[:target_id].to_i
  successes = params[:successes].to_i

  caster_data = characters.find { |c| c['id'] == caster_id }
  target_data = characters.find { |c| c['id'] == target_id }
  halt 400, "Caster not found" unless caster_data
  halt 400, "Target not found" unless target_data
  caster = CharacterSheet.new(caster_data)
  target_char = CharacterSheet.new(target_data)
  caster_p = downtime_find_or_create_participant(combat_data, caster)
  target_p = downtime_find_or_create_participant(combat_data, target_char)

  result = downtime_apply_cast(compendium, combat_data, caster, target_char, caster_p, target_p,
    spell_name: spell_name, quantity: [params[:quantity].to_i, 1].max,
    successes: successes, gold_cost: 0, campaign: nil)
  halt 400, result[:error] if result[:error]

  Tools.save_json('combat.json', combat_data)
  Combat.add_log(result[:log])
  redirect '/downtime'
end

# Shared cast resolver used by /downtime/cast, /downtime/cast_ritual, and the
# spellcasting service handler. Loops up to `quantity` casts (forced to 1
# for Surgery) while the target hasn't hit the saturation cap, the caster
# can afford the mana, and the campaign can afford the per-cast gold (when
# supplied). Mutates combat_data and (if given) campaign in place; returns
# {:applied, :totals, :log, :error}.
def downtime_apply_cast(compendium, combat_data, caster, target_char, caster_p, target_p,
                        spell_name:, quantity: 1, successes: 0, gold_cost: 0, campaign: nil)
  resolved = compendium.resolve_spell_variant(spell_name)
  return { error: "Unknown spell" } unless resolved
  base_name = resolved[0]
  tier_val = resolved[3].to_i
  mana_cost = tier_val == 0 ? 1 : (tier_val * 2 + 2)

  # Resolve which effect type this spell uses.
  cure = compendium.cure_effects(spell_name)
  mana = (cure.nil?) ? compendium.mana_effects(spell_name) : nil
  ability = (cure.nil? && mana.nil?) ? compendium.ability_cure_effects(spell_name) : nil
  surgery = (cure.nil? && mana.nil? && ability.nil? && base_name == 'Standard Surgery')
  return { error: "Spell not supported in downtime" } unless cure || mana || ability || surgery

  quantity = 1 if surgery # 1-hour spell, no batching
  max_saturation = target_char.cha
  totals = { major: 0, moderate: 0, minor: 0, ability_major: 0, ability_moderate: 0, ability_minor: 0, mana: 0, sat: 0 }
  applied = 0
  stop_reason = nil

  quantity.times do
    if target_p['saturation'].to_i >= max_saturation
      stop_reason = :sat_cap
      break
    end
    # Recharge requires mana_cost + transfer up-front (transfer comes back
    # for self-cast but the caster still has to "have" it to spend).
    cast_required = mana_cost + (mana ? mana[:mana].to_i : 0)
    if caster_p['mana'].to_i < cast_required
      stop_reason = :mana
      break
    end
    if gold_cost > 0 && (campaign.nil? || campaign['gold'].to_i < gold_cost)
      stop_reason = :gold
      break
    end
    if cure
      h_major, h_mod, h_minor = Combat.apply_cure_cascade(target_p, cure)
      sat_add = cure[:saturation] - target_char.tier
      sat_add -= 2 * caster.tier if caster.ability_list.include?('improved_healing')
      sat_add = cure[:minimum_saturation] if sat_add < cure[:minimum_saturation]
      totals[:major] += h_major; totals[:moderate] += h_mod; totals[:minor] += h_minor
    elsif mana
      # Recharge transfers mana from the caster to the target. The caster
      # pays mana_cost (cast cost) PLUS mana[:mana] (transferred), and the
      # target receives mana[:mana] (clamped to mana_max). For a self-cast
      # the same participant hash is on both sides, so the transfer nets
      # to zero on top of the cast cost.
      target_max_mana = target_char.mana_max
      caster_p['mana'] = caster_p['mana'].to_i - mana[:mana]
      current_mana = target_p['mana'].to_i
      new_mana = [current_mana + mana[:mana], target_max_mana].min
      target_p['mana'] = new_mana
      sat_add = mana[:saturation] - target_char.tier
      sat_add = mana[:minimum_saturation] if sat_add < mana[:minimum_saturation]
      totals[:mana] += (new_mana - current_mana)
    elsif ability
      h_major, h_mod, h_minor = Combat.apply_ability_cure_cascade(target_p, ability)
      sat_add = ability[:saturation] - target_char.tier
      sat_add -= 2 * caster.tier if caster.ability_list.include?('improved_healing')
      sat_add = ability[:minimum_saturation] if sat_add < ability[:minimum_saturation]
      totals[:ability_major] += h_major; totals[:ability_moderate] += h_mod; totals[:ability_minor] += h_minor
    else # surgery
      return { error: "Surgery requires non-negative successes" } if successes < 0
      major_before = target_p['major_damage'].to_i
      target_p['moderate_damage'] = target_p['moderate_damage'].to_i + (2 * major_before)
      target_p['temporary_hit_points'] = 0
      healed_major = [successes, major_before].min
      target_p['major_damage'] = major_before - healed_major
      base_sat = 10 * healed_major
      min_sat = 5 * healed_major
      sat_add = base_sat
      sat_add -= 2 * caster.tier if caster.ability_list.include?('improved_healing')
      sat_add = min_sat if sat_add < min_sat
      totals[:major] += healed_major
      # Track the moderate damage we just inflicted so the log line matches
      # what a player saw in the preview.
      totals[:moderate] -= (2 * major_before)
    end
    target_p['saturation'] = target_p['saturation'].to_i + sat_add
    caster_p['mana'] = caster_p['mana'].to_i - mana_cost
    if gold_cost > 0 && campaign
      campaign['gold'] = campaign['gold'].to_i - gold_cost
    end
    totals[:sat] += sat_add
    applied += 1
  end

  if applied == 0
    msg = case stop_reason
          when :sat_cap then "#{target_char.name} is already at maximum magical saturation (#{target_p['saturation']}/#{max_saturation})"
          when :mana    then "#{caster.name} does not have enough mana (#{caster_p['mana']}/#{mana_cost + (mana ? mana[:mana].to_i : 0)})"
          when :gold    then "Not enough gold (have #{(campaign && campaign['gold']) || 0}g, need #{gold_cost}g)"
          else "Cast failed"
          end
    return { error: msg }
  end

  suffix = applied > 1 ? " x#{applied}" : ''
  log_effect =
    if cure   then "healed #{totals[:major]}/#{totals[:moderate]}/#{totals[:minor]}"
    elsif mana then "restored #{totals[:mana]} mana"
    elsif ability then "cured #{totals[:ability_major]}/#{totals[:ability_moderate]}/#{totals[:ability_minor]} ability damage"
    else "surgery: cured #{totals[:major]} major"
    end
  gold_suffix = gold_cost > 0 ? ", #{gold_cost * applied}g" : ''
  log = "#{caster.name} casts #{spell_name}#{suffix} on #{target_char.name} (#{mana_cost * applied} mana#{gold_suffix}) - #{log_effect}, +#{totals[:sat]} saturation"
  { applied: applied, totals: totals, log: log }
end

post '/downtime/cast_ritual' do
  compendium = Compendium.new
  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')
  campaign = Tools.load_json('campaign.json')

  caster_id = params[:caster_id].to_i
  spell_name = params[:spell_name].to_s
  target_id = params[:target_id].to_i

  caster_data = characters.find { |c| c['id'] == caster_id }
  target_data = characters.find { |c| c['id'] == target_id }
  halt 400, "Caster not found" unless caster_data
  halt 400, "Target not found" unless target_data
  caster = CharacterSheet.new(caster_data)
  target_char = CharacterSheet.new(target_data)

  known = (caster.ritual_list || []).flatten.compact.map(&:to_s)
  halt 400, "Caster does not know that ritual" unless known.include?(spell_name)

  caster_p = downtime_find_or_create_participant(combat_data, caster)
  target_p = downtime_find_or_create_participant(combat_data, target_char)

  resolved = compendium.resolve_spell_variant(spell_name)
  halt 400, "Unknown spell" unless resolved
  tier_val = resolved[3].to_i
  ritual_costs = compendium.data['ritual_gold_cost_by_tier'] || [1, 10, 50, 100, 200, 400]
  gold_cost = ritual_costs[tier_val] || ritual_costs.last

  result = downtime_apply_cast(compendium, combat_data, caster, target_char, caster_p, target_p,
    spell_name: spell_name, quantity: [params[:quantity].to_i, 1].max,
    successes: params[:successes].to_i, gold_cost: gold_cost, campaign: campaign)
  halt 400, result[:error] if result[:error]

  Tools.save_json('combat.json', combat_data)
  Tools.save_json('campaign.json', campaign)
  Combat.add_log(result[:log])
  redirect '/downtime'
end

post '/downtime/use_item' do
  compendium = Compendium.new
  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')

  # The form uses a combined "owner|item" select that writes to hidden
  # owner_id / item_id inputs on change; accept either representation.
  if params[:owner_item_combined].to_s.include?('|')
    owner_id_str, item_id_str = params[:owner_item_combined].to_s.split('|', 2)
    owner_id = owner_id_str.to_i
    item_id = item_id_str.to_i
  else
    owner_id = params[:owner_id].to_i
    item_id = params[:item_id].to_i
  end
  target_id = params[:target_id].to_i

  owner_data = characters.find { |c| c['id'] == owner_id }
  target_data = characters.find { |c| c['id'] == target_id }
  halt 400, "Owner not found" unless owner_data
  halt 400, "Target not found" unless target_data
  owner = CharacterSheet.new(owner_data)
  target_char = CharacterSheet.new(target_data)

  item = owner.item_list.find { |i| i['item_id'].to_i == item_id }
  halt 400, "Item not found" unless item
  effect = compendium.item_effects(item)
  halt 400, "This item cannot be used" unless effect

  target_p = downtime_find_or_create_participant(combat_data, target_char)
  max_saturation = target_char.cha
  current_saturation = target_p['saturation'].to_i
  at_max = current_saturation >= max_saturation
  effect_log = ''

  if effect[:kind] == :potion
    halt 400, "#{target_char.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max
    potion_sat = Compendium.potion_saturation(effect[:item_tier], target_char.tier)
    case effect[:type]
    when :cure
      healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target_p, effect)
      cure_sat = effect[:saturation] - target_char.tier
      cure_sat = effect[:minimum_saturation] if cure_sat < effect[:minimum_saturation]
      total_sat = cure_sat + potion_sat
      target_p['saturation'] = current_saturation + total_sat
      effect_log = "healed #{healed_major}/#{healed_moderate}/#{healed_minor}, +#{total_sat} saturation (#{cure_sat} cure + #{potion_sat} potion)"
    when :mana
      target_max_mana = target_char.mana_max
      current_mana = target_p['mana'].to_i
      new_mana = [current_mana + effect[:mana], target_max_mana].min
      target_p['mana'] = new_mana
      target_p['saturation'] = current_saturation + potion_sat
      effect_log = "mana #{current_mana} -> #{new_mana}, +#{potion_sat} saturation"
    when :ward
      current_temp = target_p['temporary_hit_points'].to_i
      new_temp = [current_temp, effect[:temp_hp]].max
      target_p['temporary_hit_points'] = new_temp
      target_p['saturation'] = current_saturation + potion_sat
      effect_log = "temp HP #{current_temp} -> #{new_temp}, +#{potion_sat} saturation"
    end
  elsif effect[:kind] == :scroll
    case effect[:type]
    when :cure
      halt 400, "#{target_char.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max
      healed_major, healed_moderate, healed_minor = Combat.apply_cure_cascade(target_p, effect)
      sat_add = effect[:saturation] - target_char.tier
      sat_add -= 2 * owner.tier if owner.ability_list.include?('improved_healing')
      sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
      target_p['saturation'] = current_saturation + sat_add
      effect_log = "healed #{healed_major}/#{healed_moderate}/#{healed_minor}, +#{sat_add} saturation"
    when :mana
      halt 400, "#{target_char.name} is already at maximum magical saturation (#{current_saturation}/#{max_saturation})" if at_max
      target_max_mana = target_char.mana_max
      current_mana = target_p['mana'].to_i
      new_mana = [current_mana + effect[:mana], target_max_mana].min
      target_p['mana'] = new_mana
      sat_add = effect[:saturation] - target_char.tier
      sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
      target_p['saturation'] = current_saturation + sat_add
      effect_log = "mana #{current_mana} -> #{new_mana}, +#{sat_add} saturation"
    when :ward
      current_temp = target_p['temporary_hit_points'].to_i
      new_temp = [current_temp, effect[:temp_hp]].max
      target_p['temporary_hit_points'] = new_temp
      effect_log = "temp HP #{current_temp} -> #{new_temp}"
    when :generic
      effect_log = "used #{effect[:variant_name] || item['name']} (no implemented effect)"
    end
  end

  # Consume one charge (same bookkeeping as combat /item).
  if item['item_id'].to_i > 0
    equipment = Tools.load_json('equipment.json')
    stored_idx = item_id - 1
    if stored_idx >= 0 && stored_idx < equipment.length
      stored = equipment[stored_idx]
      stored['quantity'] = (stored['quantity'] || 1) - 1
      equipment.delete_at(stored_idx) if stored['quantity'] <= 0
      Tools.save_json('equipment.json', equipment)
    end
  else
    chars = Tools.load_json('characters.json')
    owner_rec = chars.find { |c| c['id'] == owner_id }
    if owner_rec && owner_rec['items']
      inline_idx = -item['item_id'].to_i - 1
      if inline_idx >= 0 && inline_idx < owner_rec['items'].length
        inline = owner_rec['items'][inline_idx]
        inline['quantity'] = (inline['quantity'] || 1) - 1
        owner_rec['items'].delete_at(inline_idx) if inline['quantity'] <= 0
        Tools.save_json('characters.json', chars)
      end
    end
  end

  Tools.save_json('combat.json', combat_data)
  Combat.add_log("#{owner.name} uses #{item['name']} on #{target_char.name} - #{effect_log}")
  redirect '/downtime'
end

post '/downtime/service' do
  redirect '/downtime' unless local_request?
  compendium = Compendium.new
  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')
  campaign = Tools.load_json('campaign.json')

  spell = params[:spell].to_s
  caster_title = params[:service_caster].to_s
  target_id = params[:target_id].to_i
  quantity = [params[:quantity].to_i, 1].max
  services = compendium.data['spellcasting_services'] || []
  service = services.find { |s| s['spell'].to_s == spell && s['title'].to_s == caster_title }
  halt 400, "Service not found" unless service

  target_data = characters.find { |c| c['id'] == target_id }
  halt 400, "Target not found" unless target_data
  target_char = CharacterSheet.new(target_data)
  target_p = downtime_find_or_create_participant(combat_data, target_char)

  # Services support cure, mana (Recharge), and ability-cure (Restoration)
  # effects. Restoration follows the same cascade as Cure but on the queued
  # ability damage instead of physical damage.
  cure = compendium.cure_effects(service['spell'])
  mana = cure.nil? ? compendium.mana_effects(service['spell']) : nil
  ability = (cure.nil? && mana.nil?) ? compendium.ability_cure_effects(service['spell']) : nil
  halt 400, "Service spell effect not recognized" unless cure || mana || ability

  max_saturation = target_char.cha
  unit_cost = service['cost'].to_i
  cleric = service['class'].to_s == 'cleric'

  totals = { major: 0, moderate: 0, minor: 0, ability_major: 0, ability_moderate: 0, ability_minor: 0, mana: 0, sat: 0 }
  applied = 0
  stop_reason = nil
  quantity.times do
    if target_p['saturation'].to_i >= max_saturation
      stop_reason = :sat_cap
      break
    end
    if campaign['gold'].to_i < unit_cost
      stop_reason = :gold
      break
    end
    if cure
      h_major, h_mod, h_minor = Combat.apply_cure_cascade(target_p, cure)
      sat_add = cure[:saturation] - target_char.tier
      sat_add -= 2 * service['tier'].to_i if cleric
      sat_add = cure[:minimum_saturation] if sat_add < cure[:minimum_saturation]
      totals[:major] += h_major; totals[:moderate] += h_mod; totals[:minor] += h_minor
    elsif mana
      target_max_mana = target_char.mana_max
      current_mana = target_p['mana'].to_i
      new_mana = [current_mana + mana[:mana], target_max_mana].min
      target_p['mana'] = new_mana
      sat_add = mana[:saturation] - target_char.tier
      sat_add = mana[:minimum_saturation] if sat_add < mana[:minimum_saturation]
      totals[:mana] += (new_mana - current_mana)
    else # ability (Restoration)
      h_major, h_mod, h_minor = Combat.apply_ability_cure_cascade(target_p, ability)
      sat_add = ability[:saturation] - target_char.tier
      sat_add -= 2 * service['tier'].to_i if cleric
      sat_add = ability[:minimum_saturation] if sat_add < ability[:minimum_saturation]
      totals[:ability_major] += h_major; totals[:ability_moderate] += h_mod; totals[:ability_minor] += h_minor
    end
    target_p['saturation'] = target_p['saturation'].to_i + sat_add
    campaign['gold'] = campaign['gold'].to_i - unit_cost
    totals[:sat] += sat_add
    applied += 1
  end

  if applied == 0
    msg = stop_reason == :sat_cap ?
      "#{target_char.name} is already at maximum magical saturation (#{target_p['saturation']}/#{max_saturation})" :
      "Not enough gold (have #{campaign['gold']}, need #{unit_cost})"
    halt 400, msg
  end

  Tools.save_json('combat.json', combat_data)
  Tools.save_json('campaign.json', campaign)
  label = "#{service['spell']} (#{service['title']})#{applied > 1 ? " x#{applied}" : ''}"
  total_cost = unit_cost * applied
  summary =
    if cure   then "healed #{totals[:major]}/#{totals[:moderate]}/#{totals[:minor]}"
    elsif mana then "restored #{totals[:mana]} mana"
    else "cured #{totals[:ability_major]}/#{totals[:ability_moderate]}/#{totals[:ability_minor]} ability damage"
    end
  Combat.add_log("#{target_char.name} paid #{total_cost}g for #{label} service - #{summary}, +#{totals[:sat]} saturation")
  redirect '/downtime'
end

# Number of recovery periods a `days` span covers for a given unit. The
# "week"/"month" thresholds only kick in once the party has rested a full
# 7 / 28 days -- partial weeks or months yield zero week/month benefit (per
# the campaign rules). Hours count as `days * 24` since a day is always
# more than 24 hours of rest.
def downtime_period_count(days, unit)
  case unit.to_s
  when 'hour'  then days * 24
  when 'day'   then days
  when 'week'  then days >= 7  ? (days / 7)  : 0
  when 'month' then days >= 28 ? (days / 28) : 0
  else 0
  end
end

post '/downtime/rest' do
  redirect '/downtime' unless local_request?
  rules = Tools.load_json('rules.json')
  characters = Tools.load_json('characters.json')
  combat_data = Tools.load_json('combat.json')
  campaign = Tools.load_json('campaign.json')

  mode = params[:mode].to_s
  days = params[:days].to_i
  halt 400, "Days must be positive" if days <= 0
  use_high = mode == 'long_term_recovery'

  heal_rate = rules['advancement']['natural']['heal_rate']
  ability_heal_rate = rules.dig('advancement', 'natural', 'ability_heal_rate') || heal_rate
  pc_list = characters.select { |c| c['group'] == 'PC' }

  summary_lines = []
  pc_list.each do |char_data|
    character = CharacterSheet.new(char_data)
    participant = downtime_find_or_create_participant(combat_data, character)
    tier = character.tier

    # Per-PC heal rows = 3 entries (minor / moderate / major), each [low, high, unit].
    row_base = tier * 3
    rows = [heal_rate[row_base], heal_rate[row_base + 1], heal_rate[row_base + 2]]
    keys = %w[minor_damage moderate_damage major_damage]
    healed = [0, 0, 0]
    rows.each_with_index do |row, i|
      next unless row
      low, high, unit = row
      per = use_high ? high.to_i : low.to_i
      periods = downtime_period_count(days, unit)
      amt = per * periods
      before = participant[keys[i]].to_i
      after = [before - amt, 0].max
      healed[i] = before - after
      participant[keys[i]] = after
    end

    # Ability damage heals on its own ability_heal_rate counter (mirrors the
    # heal_rate shape, three rows per tier). Each heal point pops one queued
    # ability damage point at that severity in FIFO order across attributes.
    ability_rows = [ability_heal_rate[row_base], ability_heal_rate[row_base + 1], ability_heal_rate[row_base + 2]]
    ability_severities = %w[minor moderate major]
    ability_healed = [0, 0, 0]
    ability_rows.each_with_index do |row, i|
      next unless row
      low, high, unit = row
      per = use_high ? high.to_i : low.to_i
      periods = downtime_period_count(days, unit)
      amt = per * periods
      ability_healed[i] = Combat.pop_ability_damage(participant, ability_severities[i], amt)
    end

    # Mana regen: floor(mana_max/4) per day, clamped to mana_max.
    mana_per_day = (character.mana_max.to_i / 4).to_i
    new_mana = [participant['mana'].to_i + mana_per_day * days, character.mana_max.to_i].min
    mana_gained = new_mana - participant['mana'].to_i
    participant['mana'] = new_mana

    # Saturation: floor(cha/4) per day, floored at 0.
    sat_per_day = (character.cha.to_i / 4).to_i
    sat_before = participant['saturation'].to_i
    sat_after = [sat_before - sat_per_day * days, 0].max
    sat_lost = sat_before - sat_after
    participant['saturation'] = sat_after

    # Temp HP always falls off over rest / passing time.
    participant['temporary_hit_points'] = 0

    ability_total = ability_healed.sum
    ability_note = ability_total > 0 ? ", -#{ability_healed[0]}/#{ability_healed[1]}/#{ability_healed[2]} ability dmg" : ''
    summary_lines << "#{character.name}: -#{healed[0]}/#{healed[1]}/#{healed[2]} damage, +#{mana_gained} mana, -#{sat_lost} saturation#{ability_note}"
  end

  # Bump the calendar and zero the round counter -- combat-round timers only
  # make sense within a single fight.
  campaign['days_elapsed'] = campaign['days_elapsed'].to_i + days
  campaign['rounds_elapsed'] = 0

  Tools.save_json('combat.json', combat_data)
  Tools.save_json('campaign.json', campaign)
  label = use_high ? 'Long-term recovery' : 'Pass time'
  Combat.add_log("#{label} for #{days} day#{'s' if days != 1}: #{summary_lines.join('; ')}")
  redirect '/downtime'
end

# Resolve one active condition exactly like start_of_turn: apply consequences
# (bleed damage / paralysis rounds) then decay severity. Mutates `participant`
# and `combat_data`. Shared between /combat/action=start_of_turn and
# /downtime/urgent_actions so behavior stays in lockstep.
def downtime_resolve_condition(combat_data, participant, character, combat_id, cname, successes)
  value = participant['conditions'][cname].to_i
  return if value <= 0
  case cname
  when 'bleed'
    raw_damage = 1 + (value / 10)
    dealt = [raw_damage - successes, 0].max
    if dealt > 0
      temp_hp = participant['temporary_hit_points'].to_i
      absorbed = [dealt, temp_hp].min
      participant['temporary_hit_points'] = temp_hp - absorbed
      participant['minor_damage'] = participant['minor_damage'].to_i + (dealt - absorbed)
    end
  when 'ghoul_paralysis'
    raw_rounds = 1 + (value / 10)
    rounds = [raw_rounds - successes, 0].max
    if rounds > 0
      existing = (combat_data['active_effects'] ||= []).find do |e|
        e['spell_name'] == 'Paralyzed' && (e['target_combat_ids'] || []).include?(combat_id)
      end
      if existing
        existing['ends_on_round'] = existing['ends_on_round'].to_i + rounds
      else
        campaign = Tools.load_json('campaign.json')
        rounds_elapsed = campaign.is_a?(Hash) ? campaign['rounds_elapsed'].to_i : 0
        combat_data['active_effects'] << {
          'caster_id' => nil, 'caster_name' => 'Ghoul Paralysis',
          'spell_name' => 'Paralyzed',
          'target_combat_ids' => [combat_id], 'target_names' => [character.name],
          'round_cast' => combat_data['round'], 'ends_on_round' => rounds_elapsed + rounds
        }
      end
    end
  end
  # Universal decay: severity drops by 1 + successes, floor 0.
  new_value = [value - (1 + successes), 0].max
  if new_value <= 0
    participant['conditions'].delete(cname)
    participant['condition_meta'].delete('max_ghoul_tier') if cname == 'ghoul_paralysis'
  else
    participant['conditions'][cname] = new_value
  end
end

# Find a combat participant row and the backing CharacterSheet for a combat_id.
def downtime_lookup_combatant(combat_data, characters, combat_id)
  participant = combat_data['participants'].find { |p| p['id'].to_i == combat_id.to_i }
  return [nil, nil] unless participant
  char_id = participant['char_id'] || participant['id']
  char_data = characters.find { |c| c['id'] == char_id }
  return [participant, nil] unless char_data
  [participant, CharacterSheet.new(char_data)]
end

# Resolve one queued urgent action (cast or item) against a list of target
# combat_ids. All game-rule math (cure cascade, ward temp HP, Stabilize bleed
# reduction, mana/charge bookkeeping) lives here so End Round stays a thin
# orchestrator.
def downtime_apply_urgent_action(combat_data, characters, caster_p, caster, action)
  return if action.nil?
  type = action['type'].to_s
  return if type == 'nothing' || type.empty?
  targets = Array(action['targets']).map(&:to_i).reject(&:zero?)
  successes = action['successes'].to_i

  if type == 'cast'
    spell_name = action['spell'].to_s
    return if spell_name.empty?
    resolved = @compendium_cache.resolve_spell_variant(spell_name)
    return unless resolved
    base_name, _spell_data, _idx, tier_val = resolved
    mana_cost = tier_val.to_i == 0 ? 1 : (tier_val.to_i * 2 + 2)
    # DM is allowed to cast when unaffordable -- mana simply goes negative.
    caster_p['mana'] = caster_p['mana'].to_i - mana_cost

    targets.each do |tid|
      target_p, target = downtime_lookup_combatant(combat_data, characters, tid)
      next unless target_p && target
      apply_spell_effect(base_name, spell_name, caster, target_p, target, successes)
    end

  elsif type == 'item'
    item_id = action['item_id'].to_i
    item = caster.item_list.find { |i| i['item_id'].to_i == item_id }
    return unless item
    effect = @compendium_cache.item_effects(item)
    return unless effect

    targets.each do |tid|
      target_p, target = downtime_lookup_combatant(combat_data, characters, tid)
      next unless target_p && target
      apply_item_effect(effect, caster, target_p, target)
    end
    consume_item_charge(caster, item, item_id)
  end
end

# Cure/Ward/Stabilize branches shared between cast and (via apply_item_effect)
# the scroll consumable path.
def apply_spell_effect(base_name, spell_name, caster, target_p, target, successes)
  case base_name
  when 'Cure'
    cure = @compendium_cache.cure_effects(spell_name)
    return unless cure
    Combat.apply_cure_cascade(target_p, cure)
    sat_add = cure[:saturation] - target.tier
    sat_add -= 2 * caster.tier if caster.ability_list.include?('improved_healing')
    sat_add = cure[:minimum_saturation] if sat_add < cure[:minimum_saturation]
    target_p['saturation'] = target_p['saturation'].to_i + sat_add
  when 'Ward'
    ward = @compendium_cache.ward_effects(spell_name)
    return unless ward
    current_temp = target_p['temporary_hit_points'].to_i
    target_p['temporary_hit_points'] = [current_temp, ward[:temp_hp]].max
  when 'Stabilize'
    # Reduce bleed severity by 3 per success (description: "Reduce bleeding by
    # 3 for each success."). No effect if target has no bleed condition.
    target_p['conditions'] ||= {}
    current = target_p['conditions']['bleed'].to_i
    return if current <= 0
    new_val = [current - 3 * successes, 0].max
    if new_val <= 0
      target_p['conditions'].delete('bleed')
    else
      target_p['conditions']['bleed'] = new_val
    end
  end
end

def apply_item_effect(effect, user, target_p, target)
  max_saturation = target.cha
  current_saturation = target_p['saturation'].to_i
  at_max = current_saturation >= max_saturation

  if effect[:kind] == :potion
    return if at_max
    potion_sat = Compendium.potion_saturation(effect[:item_tier], target.tier)
    case effect[:type]
    when :cure
      Combat.apply_cure_cascade(target_p, effect)
      cure_sat = effect[:saturation] - target.tier
      cure_sat = effect[:minimum_saturation] if cure_sat < effect[:minimum_saturation]
      target_p['saturation'] = current_saturation + cure_sat + potion_sat
    when :mana
      new_mana = [target_p['mana'].to_i + effect[:mana], target.mana_max].min
      target_p['mana'] = new_mana
      target_p['saturation'] = current_saturation + potion_sat
    when :ward
      current_temp = target_p['temporary_hit_points'].to_i
      target_p['temporary_hit_points'] = [current_temp, effect[:temp_hp]].max
      target_p['saturation'] = current_saturation + potion_sat
    end
  elsif effect[:kind] == :scroll
    case effect[:type]
    when :cure
      return if at_max
      Combat.apply_cure_cascade(target_p, effect)
      sat_add = effect[:saturation] - target.tier
      sat_add -= 2 * user.tier if user.ability_list.include?('improved_healing')
      sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
      target_p['saturation'] = current_saturation + sat_add
    when :mana
      return if at_max
      new_mana = [target_p['mana'].to_i + effect[:mana], target.mana_max].min
      target_p['mana'] = new_mana
      sat_add = effect[:saturation] - target.tier
      sat_add = effect[:minimum_saturation] if sat_add < effect[:minimum_saturation]
      target_p['saturation'] = current_saturation + sat_add
    when :ward
      current_temp = target_p['temporary_hit_points'].to_i
      target_p['temporary_hit_points'] = [current_temp, effect[:temp_hp]].max
    end
  end
end

# Consume one charge. Mirrors the equipment.json / inline-items bookkeeping
# used by /combat/action=item and /downtime/use_item.
def consume_item_charge(owner, item, item_id)
  if item['item_id'].to_i > 0
    equipment = Tools.load_json('equipment.json')
    stored_idx = item_id - 1
    if stored_idx >= 0 && stored_idx < equipment.length
      stored = equipment[stored_idx]
      stored['quantity'] = (stored['quantity'] || 1) - 1
      equipment.delete_at(stored_idx) if stored['quantity'] <= 0
      Tools.save_json('equipment.json', equipment)
    end
  else
    chars = Tools.load_json('characters.json')
    owner_rec = chars.find { |c| c['id'] == owner.id }
    if owner_rec && owner_rec['items']
      inline_idx = -item['item_id'].to_i - 1
      if inline_idx >= 0 && inline_idx < owner_rec['items'].length
        inline = owner_rec['items'][inline_idx]
        inline['quantity'] = (inline['quantity'] || 1) - 1
        owner_rec['items'].delete_at(inline_idx) if inline['quantity'] <= 0
        Tools.save_json('characters.json', chars)
      end
    end
  end
end

post '/downtime/urgent_actions' do
  redirect '/downtime' unless local_request?
  @compendium_cache = Compendium.new
  combat_data = Tools.load_json('combat.json')
  characters = Tools.load_json('characters.json')

  payload_raw = params[:payload].to_s
  payload = payload_raw.empty? ? {} : JSON.parse(payload_raw)
  saves = payload['saves'] || {}
  actions = payload['actions'] || {}

  # Resolve in initiative order so that a combatant's queued action (e.g. a
  # Stabilize that drops a target's bleed severity, or a Ward that adds temp
  # HP) takes effect before that target's own save phase later in the round.
  # Combat.new loads a sorted snapshot; we mutate combat_data as we go so each
  # subsequent combatant sees the up-to-date state.
  combat = Combat.new
  combat.combat_turn_list.each do |ct|
    cid = ct.combat_id
    participant = combat_data['participants'].find { |p| p['id'].to_i == cid.to_i }
    next unless participant
    char_id = participant['char_id'] || participant['id']
    char_data = characters.find { |c| c['id'] == char_id }
    next unless char_data
    character = CharacterSheet.new(char_data)

    # 1. Save phase for this combatant.
    participant['conditions'] ||= {}
    participant['condition_meta'] ||= {}
    (saves[cid.to_s] || {}).each do |cname, successes|
      downtime_resolve_condition(combat_data, participant, character, cid, cname.to_s, successes.to_i)
    end

    # 2. Action phase for this combatant. Both phases mutate combat_data so a
    # heal cast here is visible to later combatants.
    Array(actions[cid.to_s]).each do |action|
      downtime_apply_urgent_action(combat_data, characters, participant, character, action)
    end
  end

  # Refresh combat pools, advance round counter.
  (combat_data['participants'] || []).each do |participant|
    char_id = participant['char_id'] || participant['id']
    char_data = characters.find { |c| c['id'] == char_id }
    next unless char_data
    character = CharacterSheet.new(char_data)
    participant['combat_pool'] = character.combat_pool
  end
  combat_data['round'] = combat_data['round'].to_i + 1

  Tools.save_json('combat.json', combat_data)
  redirect '/downtime'
end

post '/downtime/quick_resolve' do
  redirect '/downtime' unless local_request?
  combat_data = Tools.load_json('combat.json')

  payload_raw = params[:payload].to_s
  payload = payload_raw.empty? ? {} : JSON.parse(payload_raw)
  results = payload['results'] || {}

  # Apply per-combatant, per-condition results from the simulation. The client
  # has already done all the dice rolling and accounting (bleed damage,
  # paralysis rounds, ability damage, severity decay); the server just stamps
  # the outcome onto combat.json.
  results.each do |cid_str, conds|
    participant = combat_data['participants'].find { |p| p['id'].to_i == cid_str.to_i }
    next unless participant
    participant['conditions'] ||= {}
    participant['condition_meta'] ||= {}
    conds.each do |cname, sim|
      cname = cname.to_s
      damage = sim['damage'].to_i
      temp_absorbed = sim['tempAbsorbed'].to_i
      rounds = sim['rounds'].to_i
      ability_dealt = sim['abilityDealt'] || {}
      final_severity = sim['finalSeverity'].to_i

      if cname == 'bleed'
        # Temp HP soaks damage first; remainder lands as minor damage.
        if temp_absorbed > 0
          participant['temporary_hit_points'] = [participant['temporary_hit_points'].to_i - temp_absorbed, 0].max
        end
        participant['minor_damage'] = participant['minor_damage'].to_i + damage if damage > 0
      elsif cname == 'ghoul_paralysis' && rounds > 0
        existing = (combat_data['active_effects'] ||= []).find do |e|
          e['spell_name'] == 'Paralyzed' && (e['target_combat_ids'] || []).include?(cid_str.to_i)
        end
        if existing
          existing['ends_on_round'] = existing['ends_on_round'].to_i + rounds
        else
          char_id = participant['char_id'] || participant['id']
          char_data = Tools.load_json('characters.json').find { |c| c['id'] == char_id }
          char_name = char_data ? char_data['name'] : 'Unknown'
          campaign = Tools.load_json('campaign.json')
          rounds_elapsed = campaign.is_a?(Hash) ? campaign['rounds_elapsed'].to_i : 0
          combat_data['active_effects'] << {
            'caster_id' => nil, 'caster_name' => 'Ghoul Paralysis',
            'spell_name' => 'Paralyzed',
            'target_combat_ids' => [cid_str.to_i], 'target_names' => [char_name],
            'round_cast' => combat_data['round'], 'ends_on_round' => rounds_elapsed + rounds
          }
        end
      end

      # Generic ability-damage application: client sends totals as
      # {severity: {attr: count}} from minor_strength_poison-style
      # conditions. Accumulate onto participant.ability_damage[attr][severity].
      ability_dealt.each do |sev, attr_map|
        next unless attr_map.is_a?(Hash)
        attr_map.each do |attr, n|
          n = n.to_i
          next if n <= 0
          participant['ability_damage'] ||= {}
          participant['ability_damage'][attr.to_s] ||= {}
          participant['ability_damage'][attr.to_s][sev.to_s] =
            participant['ability_damage'][attr.to_s][sev.to_s].to_i + n
        end
      end

      # Final severity: 0 means the condition resolved, else it stalled at 30
      # saves and the remaining severity rolls forward.
      if final_severity <= 0
        participant['conditions'].delete(cname)
        participant['condition_meta'].delete('max_ghoul_tier') if cname == 'ghoul_paralysis'
      else
        participant['conditions'][cname] = final_severity
      end
    end
  end

  Tools.save_json('combat.json', combat_data)
  redirect '/downtime'
end

get '/all_characters/:index' do
  redirect '/character/0' unless local_request?
  character_list = Tools.load_json('characters.json')
  load_character_view(character_list, params[:index].to_i, '/all_characters')
end
