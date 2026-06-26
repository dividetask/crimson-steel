require 'json'

require_relative 'creatures/config'
require_relative 'creatures/advancement'
require_relative 'creatures/races'
require_relative 'creatures/deities'
require_relative 'creatures/formula'
require_relative 'creatures/record'
require_relative 'creatures/dataset'
require_relative 'creatures/accessor'
require_relative 'creatures/random_encounter'

# Top-level Creatures module surface. Exposes the public entry
# points listed in creatures_design.md against the multi-file
# dataset loaded by Creatures::Dataset.
#
# Still stubbed: aggregated_modifiers (returns [] until the
# Abilities domain lands), Weighted Choice / Gated Weighted Choice
# random encounter row variants (mirror Equipment's Loot Roll Row, which
# hasn't been designed yet).
module Creatures
  module_function

  # ---- look-up entry points -------------------------------------------

  def lookup(id)
    rec = Dataset.get(id)
    rec && Accessor.new(rec)
  end

  def list(group: nil, tags: nil)
    Dataset.ids_in_load_order.filter_map do |id|
      rec = Dataset.get(id)
      next unless rec
      next if group && rec[:group] != group.to_s
      next if tags && !Array(tags).all? { |t| rec[:tags].include?(t.to_s) }
      [rec[:id], rec[:name]]
    end
  end

  def find_by_name(name)
    Dataset.ids_in_load_order.each do |id|
      rec = Dataset.get(id)
      return Accessor.new(rec) if rec && rec[:name] == name
    end
    nil
  end

  # ---- chronicle / status compat shims --------------------------------

  # Old shape: { id:, name:, tier:, player_controlled: bool }. The
  # Chronicle Creature Reference Entry resolver and the
  # player-Creatures dropdowns read this directly. Lookup goes
  # through the live Dataset / Accessor now.
  def get(id)
    a = lookup(id)
    return nil unless a
    { id: a.id, name: a.name, tier: a.tier,
      player_controlled: a.group == 'pc' || a.tags.include?('player_character') }
  end

  def player_controlled
    list(tags: ['player_character']).map { |(id, name)| { id: id, name: name } }
  end

  # ---- update entry points --------------------------------------------

  def set_tier_override(id, tier_value)
    rec = Dataset.get(id) or raise ArgumentError, "no Creature with id #{id}"
    rec[:tier] = tier_value.nil? ? nil : Integer(tier_value)
    nil
  end

  def set_tier_attribute_advancement(id, list)
    rec = Dataset.get(id) or raise ArgumentError, "no Creature with id #{id}"
    list.each do |a|
      unless Config.attribute_keys.include?(a.to_sym)
        raise ArgumentError, "unknown attribute key #{a.inspect}"
      end
    end
    rec[:tier_attribute_advancement] = list.map(&:to_sym)
    nil
  end

  def set_class_level(id, class_key, level)
    rec = Dataset.get(id) or raise ArgumentError, "no Creature with id #{id}"
    class_key = class_key.to_s
    unless Advancement.classes.key?(class_key)
      raise ArgumentError, "unknown class #{class_key.inspect}"
    end
    rec[:classes][class_key] ||= { level: 0, skills: [], choices: {} }
    rec[:classes][class_key][:level] = Integer(level)
    Record.send(:validate_archetype_exclusivity!, rec[:classes], rec[:id], nil)
    nil
  end

  def set_trained_skills(id, class_key, skills)
    rec = Dataset.get(id) or raise ArgumentError, "no Creature with id #{id}"
    key = class_key.to_s
    raise ArgumentError, "Creature does not have class #{key.inspect}" unless rec[:classes].key?(key)
    skills = skills.map(&:to_s)
    skills.each do |s|
      raise ArgumentError, "bare Set Skill key #{s.inspect} not allowed" if s.end_with?('_')
    end
    rec[:classes][key][:skills] = skills
    nil
  end

  def set_class_choices(id, class_key, choices)
    rec = Dataset.get(id) or raise ArgumentError, "no Creature with id #{id}"
    key = class_key.to_s
    raise ArgumentError, "Creature does not have class #{key.inspect}" unless rec[:classes].key?(key)
    raise ArgumentError, '`choices` must be a Hash' unless choices.is_a?(Hash)
    rec[:classes][key][:choices] = choices.transform_keys(&:to_s)
    nil
  end

  # Promote a generated/spawned Creature to a named NPC: optionally rename it
  # and set its group to `npc`, then persist its source file. An NPC is kept
  # (grouped as an ally) through post-combat cleanup rather than deleted with
  # the enemy spawns.
  def promote_to_npc(id, name = nil)
    rec = Dataset.get(id) or raise ArgumentError, "no Creature with id #{id}"
    n = name.to_s.strip
    rec[:name]  = n unless n.empty?
    rec[:group] = 'npc'
    # An NPC is a concrete character, not a spawn template — drop the
    # enemy_template tag so the Character Sheet renders the real sheet rather
    # than the template (spawn tables) view.
    rec[:tags] = Array(rec[:tags]).reject { |t| t == 'enemy_template' }
    Dataset.persist_source!(rec[:source]) if rec[:source]
    rec
  end

  # ---- random encounter / spawn / delete ------------------------------

  def spawn_from_template(template_id, name_override: nil, loot_table: nil, rng: Random.new)
    RandomEncounter.spawn_from_template(template_id, name_override: name_override, loot_table: loot_table, rng: rng)
  end

  def delete(id)
    RandomEncounter.delete_creature(id)
  end

  def roll_random_encounter(table_id, seed: nil)
    RandomEncounter.roll_random_encounter(table_id, seed: seed)
  end

  # ---- meta -----------------------------------------------------------

  def reset!
    Dataset.reset!
    Advancement.reset!
    Races.reset!
    Deities.reset!
    Config.reset!
    RandomEncounter.reset!
  end
end
