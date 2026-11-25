require_relative 'data_dir'
require 'json'
require 'fileutils'

# One-time changes to the campaign data in data/ (which is not in the
# repository, so it cannot be edited by a commit). Each runs once, when the
# server starts, and is recorded in data/migrations.json so it never runs
# again. Each is careful: it only adds what is missing.
module DataMigrations
  DONE_PATH = DataDir.path('migrations.json').freeze

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
    end
  }.freeze

  module_function

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
