require 'spec_helper'
require 'tmpdir'
require_relative '../../app'

# Post-combat cleanup groups NPC allies (`group: npc`) apart from enemies: NPCs
# are sorted to the top (the stub renders them under an "NPCs" heading and
# defaults them to Ignore + Keep), enemies follow. Because NPCs are kept by
# default they stay on the roster and remain selectable in the loot pile's
# "Give to…" dropdown (combat_creature_options).
RSpec.describe 'Post-combat NPC/enemy grouping', type: :request do
  Fake = Struct.new(:name, :group, :tags, :record)

  let(:accessors) do
    { 'pc1'  => Fake.new('Aria',   nil,     ['player_character'], {}),
      'npc1' => Fake.new('Borin',  'npc',   [],                   {}),
      'npc2' => Fake.new('Cira',   'npc',   [],                   {}),
      'en1'  => Fake.new('Ogre',   'enemy', [],                   {}),
      'en2'  => Fake.new('Goblin', 'enemy', [],                   {}) }
  end
  let(:tmp) { Dir.mktmpdir('pcc') }
  let(:helpers) { Sinatra::Application.new! }

  before do
    allow(Creatures).to receive(:lookup) { |id| accessors[id.to_s] }
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'enc.json'),
      creature_lookup: ->(id) { accessors[id.to_s] },
      conditions_for: ->(_id) { nil },
      current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } },
      rounds_per_day: 1000)
    # Mixed order on purpose: enemy, PC, NPC, enemy, NPC.
    %w[en1 pc1 npc1 en2 npc2].each { |cid| Encounter.state.add_combatant(cid) }
  end
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  it 'lists NPC allies first, then enemies, and drops PCs' do
    rows = helpers.send(:post_combat_rows)
    expect(rows.map { |r| r[:name] }).to eq(%w[Borin Cira Ogre Goblin])
    expect(rows.map { |r| r[:npc] }).to eq([true, true, false, false])
  end

  it 'keeps NPCs selectable in the loot "Give to…" dropdown' do
    ids = helpers.send(:combat_creature_options).map { |o| o[:id].to_s }
    expect(ids).to include('npc1', 'npc2')
  end
end
