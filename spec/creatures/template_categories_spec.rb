require 'spec_helper'
require 'creatures'
require 'live_roster'
require 'tmpdir'

# Roster Sidebar category headings come from template_categories.yaml:
# display name and order there, unlisted keys after, by key.
RSpec.describe 'Template categories' do
  around(:each) do |ex|
    Dir.mktmpdir('creatures-data') do |dir|
      Creatures::Dataset.data_dir = dir
      ex.run
    ensure
      Creatures::Dataset.reset!
    end
  end

  it 'names catalogued keys and Title Cases the rest' do
    expect(LiveRoster.category_name('general_tier_0_red')).to eq('General Tier 0 (Red)')
    expect(LiveRoster.category_name('some_new_place')).to eq('Some New Place')
  end

  it 'sorts catalogued keys in catalog order, then the rest by key' do
    keys = %w[zeta slave_lords_general_mobs alpha general_tier_3_green general_tier_0_red]
    expect(LiveRoster.sort_categories(keys))
      .to eq(%w[general_tier_0_red general_tier_3_green slave_lords_general_mobs alpha zeta])
  end

  it 'files every shipped enemy template under a catalogued category' do
    catalog = LiveRoster.category_catalog.keys
    Creatures::Dataset.load!
    Creatures::Dataset.all.each_value do |rec|
      next unless rec[:tags].include?('enemy_template')
      expect(catalog).to include(LiveRoster.category_of(rec)), "#{rec[:id]} #{rec[:name]}"
    end
  end

  it 'gives each General Tier at least 10 templates of that tier' do
    Creatures::Dataset.load!
    (0..3).each do |tier|
      key = LiveRoster.category_catalog.keys.find { |k| k.start_with?("general_tier_#{tier}_") }
      recs = Creatures::Dataset.all.values.select { |r| r[:tags].include?('enemy_template') && LiveRoster.category_of(r) == key }
      expect(recs.size).to be >= 10
      expect(recs.map { |r| r[:tier] }.uniq).to eq([tier])
    end
  end

  it 'every Random Encounter Table spawns only shipped templates, except the Hill Fort tables' do
    Creatures::Dataset.load!
    Creatures::RandomEncounter.tables.each do |id, table|
      next if id.start_with?('hill_fort_')
      ids = table['rolls'].flat_map { |r| Array(r['spawn']) }.map { |s| s['template_id'].to_i }
      ids.each { |t| expect(Creatures::Dataset.get(t)).not_to be_nil, "#{id} -> #{t}" }
    end
  end
end
