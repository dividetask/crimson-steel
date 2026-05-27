require 'json'

# Thin Creatures domain stub. Chronicle's Creature Reference Entries
# look up name and tier via this module. A full Creatures domain
# isn't part of this project yet — until then, creatures are read
# from a small example file under docs/common/creatures/ and merged
# with the player Creatures already in lib/dummy_data.rb.
module Creatures
  DATA_PATH    = File.expand_path('../data/creatures_data.json', __dir__)
  EXAMPLE_PATH = File.expand_path('../docs/common/creatures/creatures_data.example.json', __dir__)

  module_function

  def all
    @all ||= load_all
  end

  def reset!
    @all = nil
  end

  def get(id)
    return nil unless id
    all.find { |c| c[:id] == Integer(id) }
  end

  def name(id, fallback: nil)
    get(id)&.dig(:name) || fallback || "Creature ##{id}"
  end

  def tier(id, fallback: nil)
    get(id)&.dig(:tier) || fallback
  end

  def player_controlled
    all.select { |c| c[:player_controlled] }
  end

  def load_all
    path = File.exist?(DATA_PATH) ? DATA_PATH : EXAMPLE_PATH
    raw = JSON.parse(File.read(path))
    (raw['creatures'] || []).map do |c|
      {
        id:                Integer(c['id']),
        name:              c['name'].to_s,
        tier:              c['tier'].nil? ? nil : Integer(c['tier']),
        player_controlled: c['player_controlled'] ? true : false
      }
    end
  end
end
