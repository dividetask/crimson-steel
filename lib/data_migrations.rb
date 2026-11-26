require 'json'
require 'fileutils'

# One-time changes to the campaign data in data/ (which is not in the
# repository, so it cannot be edited by a commit). Each runs once, when the
# server starts, and is recorded in data/migrations.json so it never runs
# again. Each is careful: it only adds what is missing.
module DataMigrations
  DONE_PATH = File.expand_path('../data/migrations.json', __dir__).freeze

  MIGRATIONS = {
    # Lira Duskmoor gets a Scroll of Fireball to test the new spell.
    '2026-11-19-lira-scroll-of-fireball' => lambda do
      lira = Creatures.player_controlled.find { |c| c[:name].to_s.start_with?('Lira') }
      next 'no Lira in this campaign; nothing to do' unless lira
      owner = "character:#{lira[:id]}"
      inv = Equipment.instance.get_inventory(owner)
      next "#{lira[:name]} already has a Scroll of Fireball" if inv.any? { |s| s.item_type.to_s == 'Scroll of Fireball' }
      Equipment.instance.add_item(owner, { 'item' => 'Scroll of Fireball', 'tier' => 3, 'quantity' => 1 })
      "gave #{lira[:name]} a Scroll of Fireball"
    end,

    # Shield became Spiritual Shield (Invocation only) for Clerics and Arcane
    # Shield for everyone else, both on the Trivial / Lesser / Standard ladder;
    # Spiritual Weapon / Hammer became Tier 1 "Lesser" spells.
    '2026-11-25-shield-and-spiritual-weapon-renames' => lambda do
      DataMigrations.rename_known_spells!(SPELL_RENAMES, shields: true)
    end,

    # Silence (was Tier 2) and Divine Favor (was Tier 1) became Tier 0-5 series.
    '2026-11-26-silence-and-divine-favor-series' => lambda do
      DataMigrations.rename_known_spells!(SERIES_RENAMES)
    end
  }.freeze

  SHIELD_RENAMES = {
    'lesser_shield'   => 'trivial_%s_shield',
    'standard_shield' => 'lesser_%s_shield',
    'greater_shield'  => 'standard_%s_shield'
  }.freeze
  SPELL_RENAMES = {
    'spiritual_weapon' => 'lesser_spiritual_weapon',
    'spiritual_hammer' => 'lesser_spiritual_hammer'
  }.freeze
  SERIES_RENAMES = {
    'silence'      => 'standard_silence',
    'divine_favor' => 'lesser_divine_favor'
  }.freeze

  module_function

  # Renames old spell keys in every data/ Creature's `choices.spellcasting`.
  # Matches snake_case keys and display names ("Standard Shield") alike.
  # `shields:` also applies the class-dependent SHIELD_RENAMES.
  def rename_known_spells!(renames, shields: false)
    ds = Creatures::Dataset
    changed_sources = []
    names = []
    ds.ids_in_load_order.each do |id|
      rec = ds.get(id) or next
      next unless File.exist?(ds.data_path_for(rec[:source].to_s))
      rec[:classes].each do |class_key, entry|
        picks = entry[:choices]['spellcasting']
        next unless picks.is_a?(Array)
        school = class_key == 'cleric' ? 'spiritual' : 'arcane'
        renamed = picks.map do |p|
          key = p.to_s.strip.downcase.tr(' ', '_')
          if shields && SHIELD_RENAMES[key] then format(SHIELD_RENAMES[key], school)
          elsif renames[key] then renames[key]
          else p
          end
        end
        next if renamed == picks
        entry[:choices]['spellcasting'] = renamed
        changed_sources << rec[:source]
        names << rec[:name]
      end
    end
    changed_sources.uniq.each { |src| ds.persist_source!(src) }
    names.empty? ? 'no characters knew a renamed spell' : "renamed spells for #{names.uniq.join(', ')}"
  end

  def run!(path: DONE_PATH, log: $stdout)
    done = File.exist?(path) ? (JSON.parse(File.read(path)) rescue []) : []
    MIGRATIONS.each do |id, change|
      next if done.include?(id)
      begin
        note = change.call
        log.puts "[data] #{id}: #{note}"
        done << id
      rescue StandardError => e
        log.puts "[data] #{id} failed (will try again next start): #{e.class}: #{e.message}"
      end
    end
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, JSON.pretty_generate(done))
  end
end
