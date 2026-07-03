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

  it 'deals no damage even when the conjure cast is aimed at a target' do
    # A conjure (reservoir channel) that also declares a damage_type must not
    # fall through to default_damage — casting only fills the Reservoir.
    post '/encounter/resolve_cast', JSON.generate(
      commit: true, spell_name: 'Spiritual Weapon', spell: { name: 'Spiritual Weapon' },
      caster: { id: @caster[:id], dice: 5, speed: 0, successes: 0 },
      targets: [{ id: @target[:id] }]
    ), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(200)
    expect(@cond['2'].state.hp_damage.values.sum).to eq(0)   # the cast dealt no damage
    held = Encounter.state.combatant(@caster[:id])[:concentration].find { |e| e[:spell_name] == 'Spiritual Weapon' }
    expect(held[:reservoir]).to eq(5)
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
    parry = opts.find { |o| o['value'].to_s.start_with?('parry:') }
    expect(parry).not_to be_nil
    # A parrying defender is not Flatfooted: the attacker's Roll under this Parry
    # option carries no Flatfooted Circumstance bonus.
    atk_bpl = parry.dig('patch', 'set_bpl').find { |b| b['id'] == 'attacker' }['bonus_penalty_list']
    expect(atk_bpl).not_to(include(a_collection_including('flatfooted')))
  end

  it 'never asks for a dice count — the strike auto-rolls its full Reservoir' do
    conjure!(dice: 5)
    get "/encounter/active_spells_builder?attacker_id=#{@caster[:id]}&strike_spell=#{CGI.escape("Spiritual Weapon")}"
    blob = builder_blob(last_response.body)
    action = blob['steps'].find { |s| s['key'] == 'action' }
    # A single forced (auto) option the builder applies without a button, set
    # to the whole Reservoir — no 2..N dice choices, no header quick-picks.
    interactive = (action['options'] || []).reject { |o| o['kind'] == 'info' }
    expect(interactive.length).to eq(1)
    expect(interactive.first['auto']).to be(true)
    expect(interactive.first['value']).to eq('spiritual_weapon|5')
    expect(action['header_options'] || []).to be_empty
  end

  it "rolls the strike with the caster's casting-Skill Competency and a Guidance bonus equal to the Spell Tier" do
    # The strike rolls the casting Check: the caster's Invocation Competency
    # rides the roll, and every Spell adds Guidance equal to its Tier (2 here).
    allow_any_instance_of(Sinatra::Application).to receive(:roll_inputs_for).and_wrap_original do |orig, acc, key, **kw|
      key.to_s == 'invocation' ? { dice_cap: 6, competency_modifier: ['Competency', 3] } : orig.call(acc, key, **kw)
    end
    conjure!(dice: 5)
    get "/encounter/active_spells_builder?attacker_id=#{@caster[:id]}&strike_spell=#{CGI.escape("Spiritual Weapon")}"
    blob = builder_blob(last_response.body)
    action = blob['steps'].find { |s| s['key'] == 'action' }
    bpl = action['options'].first.dig('patch', 'set_bpl').first['bonus_penalty_list']
    expect(bpl).to include(['Competency', 3])  # from Invocation ranks
    expect(bpl).to include(['Guidance', 2])    # equal to the Spell Tier
  end

  it 'ends an active Spell — drops the concentration and clears its caster Effect' do
    conjure!(dice: 5)
    # Flag the caster with the Spell's Active Effect, keyed off the entry's
    # source ('x' in conjure!), so ending the Spell clears it too.
    Conditions.store.instance_for(@caster[:creature_id])
              .apply_named_effect('spiritual_weapon', source_id: 'x:active')

    post '/encounter/end_active_spell',
         { combatant_id: @caster[:id], spell_name: 'Spiritual Weapon' },
         'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to be_between(200, 399)

    held = Encounter.state.combatant(@caster[:id])[:concentration].find { |e| e[:spell_name] == 'Spiritual Weapon' }
    expect(held).to be_nil  # the concentration is gone
    expect(Conditions.store.instance_for(@caster[:creature_id]).active_effect_names)
      .not_to include('spiritual_weapon')  # and so is its caster-side Effect
  end

  it 'ends a Reservoir concentration Spell too (Shield of Faith, no strike)' do
    Encounter.state.send(:begin_concentration, @caster[:id], spell_name: 'Shield of Faith',
                         source: 'spell:Shield of Faith', spell_tier: 1, cast_skill: 'invocation',
                         mode: 'reservoir', reservoir_reset: 'persistent', initial_reservoir: 6)
    post '/encounter/end_active_spell',
         { combatant_id: @caster[:id], spell_name: 'Shield of Faith' },
         'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to be_between(200, 399)
    held = Encounter.state.combatant(@caster[:id])[:concentration].find { |e| e[:spell_name] == 'Shield of Faith' }
    expect(held).to be_nil
  end

  it 'retargets Spiritual Weapon: stores the target and spends a Main Action + Combat Pool' do
    conjure!(dice: 5)
    Encounter.state.reset_combat_pool(@caster[:id]) rescue nil
    pool_before = (Encounter.state.combat_pool_remaining(@caster[:id]) rescue 0)
    post '/encounter/retarget_active_spell',
         { combatant_id: @caster[:id], spell_name: 'Spiritual Weapon', target_id: @target[:id] },
         'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to be_between(200, 399)
    held = Encounter.state.combatant(@caster[:id])[:concentration].find { |e| e[:spell_name] == 'Spiritual Weapon' }
    expect(held[:target_id]).to eq(@target[:id])
    spent = Encounter.state.combatant(@caster[:id])[:combat_pool_spent].to_i
    expect(spent).to eq([Encounter::Config.retarget_cost, pool_before].min) if pool_before.positive?
  end

  it 'a retargeted Spiritual Weapon strikes its target without asking (auto Target step)' do
    conjure!(dice: 5)
    Encounter.state.set_concentration_target(@caster[:id], 'Spiritual Weapon', @target[:id])
    get "/encounter/active_spells_builder?attacker_id=#{@caster[:id]}&strike_spell=#{CGI.escape("Spiritual Weapon")}"
    blob = builder_blob(last_response.body)
    target = blob['steps'].find { |s| s['key'] == 'target' }
    interactive = (target['options'] || []).reject { |o| o['kind'] == 'info' }
    expect(interactive.length).to eq(1)
    expect(interactive.first['auto']).to be(true)
    expect(interactive.first['value']).to eq(@target[:id])
    expect(target['header_options'] || []).to be_nil.or(be_empty)
  end

  it 'retargets Shield of Faith: rebuilds the granted defend-action onto the new ally' do
    Encounter.state.send(:begin_concentration, @caster[:id], spell_name: 'Shield of Faith',
                         source: 'spell:Shield of Faith', spell_tier: 1, cast_skill: 'invocation',
                         mode: 'reservoir', reservoir_reset: 'persistent', initial_reservoir: 6)
    post '/encounter/retarget_active_spell',
         { combatant_id: @caster[:id], spell_name: 'Shield of Faith', target_id: @target[:id] },
         'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to be_between(200, 399)
    guard = Encounter.state.granted_actions.find { |g| g[:spell_name] == 'Shield of Faith' && g[:combatant_id] == @caster[:id] }
    expect(guard).not_to be_nil
    expect(guard[:defends]).to eq(@target[:id])  # now guards the chosen ally
  end

  it 'refills a Shield of Faith Reservoir — channels Combat Pool dice into it' do
    Encounter.state.send(:begin_concentration, @caster[:id], spell_name: 'Shield of Faith',
                         source: 'spell:Shield of Faith', spell_tier: 1, cast_skill: 'invocation',
                         mode: 'reservoir', reservoir_reset: 'persistent', initial_reservoir: 2)
    Encounter.state.reset_combat_pool(@caster[:id]) rescue nil
    pool = (Encounter.state.combat_pool_remaining(@caster[:id]) rescue 0)
    post '/encounter/refill_active_spell',
         { combatant_id: @caster[:id], spell_name: 'Shield of Faith', dice: 3 },
         'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to be_between(200, 399)
    held = Encounter.state.combatant(@caster[:id])[:concentration].find { |e| e[:spell_name] == 'Shield of Faith' }
    added = [3, pool].min
    expect(held[:reservoir]).to eq(2 + added)
    expect(Encounter.state.combatant(@caster[:id])[:combat_pool_spent].to_i).to eq(added) if pool.positive?
  end

  it 'refuses to refill Spiritual Weapon — its Reservoir never changes (auto)' do
    conjure!(dice: 5)
    post '/encounter/refill_active_spell',
         { combatant_id: @caster[:id], spell_name: 'Spiritual Weapon', dice: 3 },
         'REMOTE_ADDR' => '127.0.0.1'
    held = Encounter.state.combatant(@caster[:id])[:concentration].find { |e| e[:spell_name] == 'Spiritual Weapon' }
    expect(held[:reservoir]).to eq(5)  # unchanged
    expect(Encounter.state.combatant(@caster[:id])[:combat_pool_spent].to_i).to eq(0)  # nothing spent
  end

  it 'retargets and ends a Standard Shield (defend-action, no Reservoir)' do
    other = Encounter.state.add_combatant('3')
    Encounter.state.grant_action(combatant_id: @caster[:id], name: 'Standard Shield', source: 'Standard Shield',
                                 spell_name: 'Standard Shield', defends: @target[:id],
                                 cast_skill: 'invocation', dice_cap: 5, dice_source: 'combat_pool', shield_bonus: 1)
    # Retarget the shield to another Combatant: the defend-action follows.
    post '/encounter/retarget_active_spell',
         { combatant_id: @caster[:id], spell_name: 'Standard Shield', target_id: other[:id] },
         'REMOTE_ADDR' => '127.0.0.1'
    guard = Encounter.state.granted_actions.find { |g| g[:spell_name] == 'Standard Shield' }
    expect(guard[:defends]).to eq(other[:id])
    # End it: the defend-action is revoked, so the block is no longer offered.
    post '/encounter/end_active_spell',
         { combatant_id: @caster[:id], spell_name: 'Standard Shield' },
         'REMOTE_ADDR' => '127.0.0.1'
    expect(Encounter.state.granted_actions.any? { |g| g[:spell_name] == 'Standard Shield' }).to be(false)
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

  it 'the strike damage is floor(casting stat / 4) + Tier + casting Competency + net Successes' do
    # Route enrichment (weapon_type: spiritual_weapon) computes the base damage
    # from the strike's concentration entry (Tier 2, Invocation), so the strike
    # no longer deals only its Successes.
    allow_any_instance_of(Sinatra::Application).to receive(:roll_inputs_for).and_wrap_original do |orig, acc, key, **kw|
      key.to_s == 'invocation' ? { dice_cap: 6, competency_modifier: ['Competency', 3] } : orig.call(acc, key, **kw)
    end
    conjure!(dice: 6)
    post '/encounter/resolve_attack', JSON.generate(
      weapon_type: 'spiritual_weapon', active_spell_name: 'Spiritual Weapon',
      target_id: @target[:id], free_attacker_pool: true,
      attacker: { id: @caster[:id], dice: 6, speed: 0, successes: 4 },
      defense: { choice: 'none' }
    ), 'CONTENT_TYPE' => 'application/json', 'REMOTE_ADDR' => '127.0.0.1'
    expect(last_response.status).to eq(200)
    res = JSON.parse(last_response.body)
    # floor(14/4)=3 + Tier 2 + Competency 3 + net Successes 4 = 12 (was 4).
    expect(res['damage']).to eq(12)
    expect(@cond['2'].state.hp_damage.values.sum).to eq(12)
  end
end
