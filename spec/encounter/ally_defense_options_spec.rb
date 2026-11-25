require 'spec_helper'
require 'rack/test'
require 'json'
require 'cgi'
require 'tmpdir'
require_relative '../../app'

# The Attack Action Builder asks the same shaped question three times — Weapon
# & dice, the target's Defense, and the Ally Defense (a shielding caster
# interposing e.g. Standard Shield). Each group leads with a named button and
# then offers the dice counts, so the DM can pick the group at its best
# affordable count without reading the numbers.
RSpec.describe 'Attack builder — Ally Defense options', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('ally-def') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  def creature(name)
    obj = Object.new
    obj.define_singleton_method(:tier) { 2 }
    obj.define_singleton_method(:total_level) { 3 }
    obj.define_singleton_method(:attribute_value) { |_a| 14 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:trained_skills) { [] }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:tags) { name == 'Ogre Brute' ? [] : ['player_character'] }
    obj.define_singleton_method(:name) { name }
    obj.define_singleton_method(:granted_abilities) { [] }
    obj
  end

  NAMES = { '1' => 'Ogre Brute', '2' => 'Fighter', '3' => 'Aldric' }.freeze

  before do
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    allow(Creatures).to receive(:lookup) { |cid| creature(NAMES[cid.to_s]) }
    allow_any_instance_of(Sinatra::Application).to receive(:equipped_weapons)
      .and_return([{ item_type: 'slam', display_name: 'Slam', ranged: false, speed: 0,
                     damage_types: ['bludgeoning'], threshold: 0, bleed: 0, base_damage: 2 }])
    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'c.json'))
    cat = Conditions::Catalog.load
    @cond = Hash.new { |h, k| h[k] = Conditions::Instance.new(catalog: cat) }
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'e.json'),
      creature_lookup: ->(id) { creature(NAMES[id.to_s]) },
      conditions_for: ->(cid) { @cond[cid] }
    )
    @attacker = Encounter.state.add_combatant('1')
    @target   = Encounter.state.add_combatant('2')
    @caster   = Encounter.state.add_combatant('3')
    Encounter.state.grant_action(combatant_id: @caster[:id], defends: @target[:id],
                                 spell_name: 'Standard Shield', dice_source: 'combat_pool',
                                 dice_cap: 4, shield_bonus: 1)
    header 'Host', 'localhost'
  end

  def builder_blob(body)
    JSON.parse(CGI.unescapeHTML(body.match(/data-builder="([^"]*)"/)[1]))
  end

  def ally_options
    get "/encounter/attack_builder?attacker_id=#{@attacker[:id]}"
    blob = builder_blob(last_response.body)
    step = blob['steps'].find { |s| s['key'] == 'ally_defense' }
    (step['options_map'] || {})["#{@target[:id]}"]
  end

  it 'leads the shield group with a named button, like the Weapon and Defense groups' do
    opts = ally_options
    expect(opts).not_to be_nil
    shield = opts.select { |o| o['group'] == 'shield' && o['kind'] != 'info' }
    expect(shield.first['label']).to eq('Standard Shield (Aldric)')
    # The lead button picks the group's best affordable dice count, and every
    # numeric button that follows is still offered.
    expect(shield.first['value']).to eq("shield:#{@caster[:id]}|4")
    expect(shield.drop(1).map { |o| o['label'] }).to eq(%w[2 3 4])
    expect(shield.map { |o| o['value'] }.uniq.length).to eq(shield.length - 1) # lead duplicates its count
  end

  it 'names the shield in the header quick-pick as well' do
    get "/encounter/attack_builder?attacker_id=#{@attacker[:id]}"
    blob = builder_blob(last_response.body)
    step = blob['steps'].find { |s| s['key'] == 'ally_defense' }
    headers = (step['header_options_map'] || {})["#{@target[:id]}"]
    expect(headers.map { |o| o['label'] }).to eq(['No defense', 'Standard Shield'])
  end
end
