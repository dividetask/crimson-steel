require 'spec_helper'
require 'rack/test'
require 'json'
require 'tmpdir'
require_relative '../../app'

# Arcane Shield: cast once at the normal Mana cost, then each hit on the caster
# offers a Reaction that spends 1 Mana to cut the damage by the shield's
# reduction (2 at Tier 0, 4 at Tier 1, doubling per Tier after).
RSpec.describe 'Arcane Shield', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('arcane-shield') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  def creature(name)
    obj = Object.new
    obj.define_singleton_method(:tier) { 1 }
    obj.define_singleton_method(:total_level) { 3 }
    obj.define_singleton_method(:attribute_value) { |_a| 14 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:trained_skills) { [] }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:max_hit_points) { 40 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { name }
    obj.define_singleton_method(:granted_abilities) { [{ name: 'Lesser Arcane Shield', source: 'class:wizard' }] }
    obj
  end

  before do
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    allow(Creatures).to receive(:lookup) { |cid| creature(cid.to_s == '1' ? 'Wizard' : 'Goblin') }
    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'c.json'))
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'e.json'),
      creature_lookup: ->(id) { creature(id.to_s) },
      conditions_for: ->(cid) { Conditions.store.instance_for(cid) }
    )
    @wizard = Encounter.state.add_combatant('1')
    @goblin = Encounter.state.add_combatant('2')
    header 'Host', 'localhost'
  end

  def cast_shield!
    post '/encounter/resolve_cast', JSON.generate(
      commit: true, spell_name: 'Lesser Arcane Shield', spell: { name: 'Lesser Arcane Shield' },
      caster: { id: @wizard[:id], dice: 1, speed: 0, successes: 0 },
      targets: [{ id: @wizard[:id] }]
    ), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(200)
  end

  def hit_wizard(commit:, reactions: [])
    post '/encounter/resolve_attack', JSON.generate(
      target_id: @wizard[:id], commit: commit, defender_reactions: reactions,
      weapon: { item_type: 'club', damage_types: ['bludgeoning'], threshold: 0, base_damage: 6 },
      attacker: { id: @goblin[:id], dice: 4, speed: 0, successes: 3 },
      defense: { choice: 'none' }
    ), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(200)
    JSON.parse(last_response.body)
  end

  it 'the cast puts its reduction on the caster' do
    cast_shield!
    mods = Conditions.store.instance_for('1').get_modifiers('arcane_shield')
    expect(mods).to include(['Guidance', 4])
  end

  it 'offers no Reaction without an active shield' do
    res = hit_wizard(commit: false)
    keys = Array(res['defender_reactions_available']).map { |r| r['key'] }
    expect(keys).not_to include('arcane_shield')
  end

  it 'offers a 1-Mana Reaction that cuts the damage by the Tier reduction' do
    cast_shield!
    spent_after_cast = Conditions.store.instance_for('1').state.mana_spent.to_i
    preview = hit_wizard(commit: false)
    offer = preview['defender_reactions_available'].find { |r| r['key'] == 'arcane_shield' }
    expect(offer).to include('mana_cost' => 1, 'amount' => 4, 'target' => 'damage_reduction')

    expect(preview['damage']).to be > 4
    shielded = hit_wizard(commit: true, reactions: ['arcane_shield'])
    expect(shielded['damage']).to eq([preview['damage'] - 4, 0].max)
    expect(Conditions.store.instance_for('1').state.mana_spent.to_i).to eq(spent_after_cast + 1)
  end
end
