require 'creatures'
require 'creatures/random_encounter'
require 'encounter'

# Builds the Roster Sidebar structure exclusively from the live
# Creatures domain (docs/common/creatures + data/) and the Random
# Encounter Tables — never from Status sample data. Both the Character
# Sheets page and the Encounter tracker share this so they stay in sync.
#
# Shape (consumed by views/_creatures_roster_sidebar.erb):
#   { players:    [{ id, name, active, copy_count }],
#     npcs:       [{ id, name, active, copy_count }],
#     categories: [{ key, name,
#                    templates: [{ id, name, copy_count, spawned: [...] }],
#                    random_encounter_tables: [{ table_id, name }] }] }
module LiveRoster
  module_function

  def build(enc_state = Encounter.state)
    spawned = spawned_by_template(enc_state)

    players = creatures_with_tag('player_character').map do |rec|
      { id: rec[:id], name: rec[:name], active: !enc_state.pc_excluded?(rec[:id]),
        copy_count: enc_state.copy_count(rec[:id]) }
    end

    npcs = creatures_in_group('npc').map do |rec|
      { id: rec[:id], name: rec[:name], active: enc_state.includes_creature?(rec[:id]),
        copy_count: enc_state.copy_count(rec[:id]) }
    end

    # Group enemy templates by their `category:<key>` tag, and join the
    # Random Encounter Tables filed under the same category.
    by_cat = Hash.new { |h, k| h[k] = { templates: [], random_encounter_tables: [] } }
    creatures_with_tag('enemy_template').each do |rec|
      key = category_of(rec) or next
      children = spawned[rec[:id].to_s] || []
      by_cat[key][:templates] << { id: rec[:id], name: rec[:name],
                                   copy_count: children.length, spawned: children }
    end
    random_encounter_tables.each do |table_id, table|
      key = table['category'] or next
      by_cat[key][:random_encounter_tables] << { table_id: table_id, name: table['name'] || table_id }
    end

    categories = by_cat.keys.sort.map do |key|
      { key: key, name: humanize(key),
        templates: by_cat[key][:templates], random_encounter_tables: by_cat[key][:random_encounter_tables] }
    end

    { players: players, npcs: npcs, categories: categories }
  end

  # Live creatures ordered by load order, returning the raw records.
  def all_records
    Creatures::Dataset.ids_in_load_order.filter_map { |id| Creatures::Dataset.get(id) }
  end

  # Creature IDs in Roster display order — Players, then NPCs, then
  # enemy templates — so the Character Sheets page defaults to a Player
  # and pages in the same order the sidebar lists.
  def ordered_ids
    recs = all_records
    players   = recs.select { |r| Array(r[:tags]).include?('player_character') }
    npcs      = recs.select { |r| r[:group] == 'npc' }
    templates = recs.select { |r| Array(r[:tags]).include?('enemy_template') }
    seen = {}
    (players + npcs + templates).filter_map { |r| next if seen[r[:id]]; seen[r[:id]] = true; r[:id] }
  end

  def creatures_with_tag(tag)
    all_records.select { |r| Array(r[:tags]).include?(tag) }
  end

  def creatures_in_group(group)
    all_records.select { |r| r[:group] == group }
  end

  def category_of(rec)
    tag = Array(rec[:tags]).find { |t| t.start_with?('category:') }
    tag && tag.sub('category:', '')
  end

  def random_encounter_tables
    Creatures::RandomEncounter.tables
  rescue StandardError
    {}
  end

  # template id (string) => list of spawned-instance rows currently in
  # the roster (a spawned Creature records its `spawned_from` template).
  def spawned_by_template(enc_state)
    out = Hash.new { |h, k| h[k] = [] }
    enc_state.combatants.each do |c|
      rec = (Creatures::Dataset.get(c[:creature_id]) rescue nil)
      next unless rec && rec[:spawned_from]
      name = c[:name].to_s.empty? ? rec[:name] : c[:name]
      out[rec[:spawned_from].to_s] << { creature_id: c[:creature_id], combatant_id: c[:id], name: name }
    end
    out
  end

  def humanize(key)
    key.to_s.split('_').map(&:capitalize).join(' ')
  end
end
