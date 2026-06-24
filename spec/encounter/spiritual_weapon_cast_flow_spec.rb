require 'spec_helper'
require 'rack/test'
require 'json'
require 'cgi'
require 'tmpdir'
require_relative '../../app'

# End-to-end coverage for the Option-2 Spiritual Weapon flow:
#   * Casting it only conjures the weapon — it fills the persistent Reservoir
#     and flags the caster; the cast itself rolls no attack and offers the
#     target no Defense (Cast is only for casting spells).
#   * The conjured strike is NOT in the Attack pane.
#   * A new Active Spells action runs the full Attack flow against a chosen
#     target — Parry included (the strike is melee) — and resolves through the
#     same /encounter/resolve_attack as a normal attack.
RSpec.describe 'Spiritual Weapon Option-2 flow', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('sw-opt2') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  def creature(spells:)
    obj = Object.new
    obj.define_singleton_method(:tier) { 2 }
    obj.define_singleton_method(:total_level) { 3 }
    obj.define_singleton_method(:attribute_value) { |_a| 14 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:trained_skills) { [] }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { spells ? 'Cleric' : 'Goblin' }
    obj.define_singleton_method(:granted_abilities) do
      spells ? [{ name: 'Spiritual Weapon', source: 'class:cleric' }] : []
    end
    obj
  end

  before do
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    allow(Creatures).to receive(:lookup) { |cid| creature(spells: cid.to_s == '1') }
    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'c.json'))
    cat = Conditions::Catalog.load
    @cond = Hash.new { |h, k| h[k] = Conditions::Instance.new(catalog: cat) }
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'e.json'),
      creature_lookup: ->(id) { creature(spells: id.to_s == '1') },
      conditions_for: ->(cid) { @cond[cid] }
    )
    @caster = Encounter.state.add_combatant('1')
    @target = Encounter.state.add_combatant('2')
    header 'Host', 'localhost'
  end

  def builder_blob(body)
    JSON.parse(CGI.unescapeHTML(body.match(/data-builder="([^"]*)"/)[1]))
  end

  # Conjure the weapon (mirrors a committed cast): fill the Reservoir + flag.
  def conjure!(dice: 5)
    Encounter.state.send(:begin_concentration, @caster[:id], spell_name: 'Spiritual Weapon',
                         source: 'x', spell_tier: 2, cast_skill: 'invocation',
                         mode: 'auto', reservoir_reset: 'persistent', initial_reservoir: dice)
  end

  it 'casting only conjures the weapon — no attack roll, no target Defense' do
    get "/encounter/cast_builder?caster_id=#{@caster[:id]}"
    blob = builder_blob(last_response.body)
    sw = blob['steps'].find { |s| s['key'] == 'spell' }['options'].find { |o| o['spell_name'] == 'Spiritual Weapon' }
    expect(sw.dig('cast', 'roll')).to be(false)          # the cast rolls nothing
    expect(sw.dig('cast', 'reservoir')).to be(true)      # it fills a Reservoir
    defense = blob['steps'].find { |s| s['key'] == 'defense' }
    expect((defense['options_map'] || {})["#{@target[:id]}|Spiritual Weapon"]).to eq([])
  end

  it 'a committed cast deals no damage but fills the Reservoir and flags the caster' do
    post '/encounter/resolve_cast', JSON.generate(
      commit: true, spell_name: 'Spiritual Weapon', spell: { name: 'Spiritual Weapon' },
      caster: { id: @caster[:id], dice: 5, speed: 0, successes: 0 },
      targets: []
    ), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(200)
    expect(@cond['2'].state.hp_damage.values.sum).to eq(0)      # the cast struck nobody
    held = Encounter.state.combatant(@caster[:id])[:concentration].find { |e| e[:spell_name] == 'Spiritual Weapon' }
    expect(held[:reservoir]).to eq(5)
    expect(@cond['1'].active_effect_names).to include('spiritual_weapon')
  end

  it 'keeps the conjured strike out of the Attack pane' do
    conjure!
    get "/encounter/attack_builder?attacker_id=#{@caster[:id]}"
    blob = builder_blob(last_response.body)
    action = blob['steps'].find { |s| s['key'] == 'action' }
    labels = (action['options'] || []).map { |o| o['summary'] || o['label'] }.compact.join(' ')
    expect(labels).not_to include('Spiritual Weapon')
  end

  it 'offers the strike in the Active Spells pane, Parryable like a melee attack' do
    allow_any_instance_of(Sinatra::Application).to receive(:equipped_melee_weapons)
      .and_return([{ item_type: 'longsword', display_name: 'Longsword', speed: 0 }])
    conjure!

    get "/encounter/active_spells_builder?attacker_id=#{@caster[:id]}"
    blob = builder_blob(last_response.body)
    action = blob['steps'].find { |s| s['key'] == 'action' }
    labels = (action['options'] || []).map { |o| o['summary'] || o['label'] }.compact.join(' ')
    expect(labels).to include('Spiritual Weapon')

    defense = blob['steps'].find { |s| s['key'] == 'defense' }
    opts = (defense['options_map'] || {})["#{@target[:id]}|spiritual_weapon"]
    expect(opts).not_to be_nil
    expect(opts.map { |o| o['value'] }.compact.any? { |v| v.to_s.start_with?('parry:') }).to be(true)
  end

  it 'resolves an Active Spells strike as a free attack that deals force damage' do
    conjure!
    post '/encounter/resolve_attack', JSON.generate(
      target_id: @target[:id], free_attacker_pool: true,
      weapon: { item_type: 'spiritual_weapon', damage_types: ['force'], threshold: 0, base_damage: 0 },
      attacker: { id: @caster[:id], dice: 5, speed: 0, successes: 4 },
      defense: { choice: 'none' }
    ), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(200)
    res = JSON.parse(last_response.body)
    expect(res['ok']).not_to be(false)
    expect(@cond['2'].state.hp_damage.values.sum).to be > 0       # the strike landed
    expect(Encounter.state.combatant(@caster[:id])[:combat_pool_spent].to_i).to eq(0) # free
    # The Reservoir is not consumed — it strikes again next turn.
    held = Encounter.state.combatant(@caster[:id])[:concentration].find { |e| e[:spell_name] == 'Spiritual Weapon' }
    expect(held[:reservoir]).to eq(5)
  end
end
