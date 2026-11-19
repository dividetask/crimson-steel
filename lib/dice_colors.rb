require 'json'
require 'fileutils'

# Each roller's dice colour, seen the same on every phone
# (docs/project/dice_colors.md).
#
# Every player Character gets its own colour, picked automatically the first
# time it is asked for (the first one nobody has). A player can change it in
# the app's Settings, and the DM on the Status page, but never to a colour
# someone else already has. The DM's dice — enemies, NPCs, and anything the
# DM rolls for no Character — start light grey.
#
# Stored in data/dice_colors.json as { "dm" => "silver", "<character id>" => "sky", ... }.
class DiceColors
  DATA_PATH = File.expand_path('../data/dice_colors.json', __dir__).freeze
  DM = 'dm'.freeze

  # Light, soft colours; none red or green, so the green / red / blue numbers
  # that show a die's result stay readable on all of them.
  PALETTE = [
    { key: 'sky',        name: 'Sky',        hex: '#93C5FD' },
    { key: 'lavender',   name: 'Lavender',   hex: '#C4B5FD' },
    { key: 'peach',      name: 'Peach',      hex: '#FDBA74' },
    { key: 'butter',     name: 'Butter',     hex: '#FDE68A' },
    { key: 'aqua',       name: 'Aqua',       hex: '#99F6E4' },
    { key: 'orchid',     name: 'Orchid',     hex: '#F0ABFC' },
    { key: 'sand',       name: 'Sand',       hex: '#E7D3B0' },
    { key: 'periwinkle', name: 'Periwinkle', hex: '#A5B4FC' },
    { key: 'ice',        name: 'Ice',        hex: '#CFFAFE' },
    { key: 'steel',      name: 'Steel',      hex: '#B4C6E7' },
    { key: 'cream',      name: 'Cream',      hex: '#FFF4CC' },
    { key: 'blush',      name: 'Blush',      hex: '#F5C2E7' },
    { key: 'silver',     name: 'Light grey', hex: '#D4D4D8' }
  ].freeze
  DM_DEFAULT = 'silver'.freeze
  # Colours handed out automatically to players (light grey is the DM's).
  AUTO = (PALETTE.map { |c| c[:key] } - [DM_DEFAULT]).freeze

  class << self
    def instance = (@instance ||= new)
    def reset! = (@instance = nil)
    def entry(key) = PALETTE.find { |c| c[:key] == key.to_s }
  end

  def initialize(data_path = DATA_PATH)
    @data_path = data_path
    @mutex = Mutex.new
    @map = File.exist?(@data_path) ? (JSON.parse(File.read(@data_path)) rescue {}) : {}
  end

  # The colour key of a roller: a Character id, or DM. Assigns one if needed.
  def key_for(who)
    who = who.to_s
    @mutex.synchronize do
      return @map[who] if self.class.entry(@map[who])
      pick = who == DM ? (taken?(DM_DEFAULT, who) ? free_key(who) : DM_DEFAULT) : free_key(who)
      @map[who] = pick
      persist!
      pick
    end
  end

  def hex_for(who) = self.class.entry(key_for(who))&.fetch(:hex)

  # Change a roller's colour. Raises ArgumentError when unknown or taken.
  def set(who, key)
    who = who.to_s
    raise ArgumentError, 'unknown colour' unless self.class.entry(key)
    @mutex.synchronize do
      raise ArgumentError, 'someone else already has that colour' if taken?(key, who)
      @map[who] = key.to_s
      persist!
    end
    key
  end

  # Every colour, with who (if anyone else) has it: [{ key, name, hex, taken_by }].
  def options(who)
    who = who.to_s
    owners = @mutex.synchronize { @map.dup }
    PALETTE.map do |c|
      holder = owners.find { |k, v| v == c[:key] && k != who }&.first
      c.merge(taken_by: holder)
    end
  end

  def assignments = @mutex.synchronize { @map.dup }

  private

  def taken?(key, who) = @map.any? { |k, v| v == key.to_s && k != who }

  def free_key(who)
    AUTO.find { |k| !taken?(k, who) } ||
      (taken?(DM_DEFAULT, who) ? AUTO[@map.size % AUTO.size] : DM_DEFAULT)
  end

  def persist!
    FileUtils.mkdir_p(File.dirname(@data_path))
    tmp = "#{@data_path}.tmp"
    File.write(tmp, JSON.pretty_generate(@map))
    File.rename(tmp, @data_path)
  end
end
