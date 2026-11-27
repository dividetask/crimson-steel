require 'spec_helper'
require 'rack/test'
require 'json'
require 'cgi'
require 'tmpdir'
require_relative '../../app'

# A +X weapon rolls X extra dice with the attack (equipment_design.md →
# Enhancement and Enchantment): plain for an untyped weapon, flavored for an
# enchanted one, at the attacker's TN, with +X Guidance on the attack.
RSpec.describe 'Attack builder — enchantment dice', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('enchant-dice') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  def creature(tier)
    obj = Object.new
    obj.define_singleton_method(:tier) { tier }
    obj.define_singleton_method(:total_level) { 3 }
    obj.define_singleton_method(:attribute_value) { |_a| 12 }
    obj.define_singleton_method(:ranks_for) { |_k| 3 }
    obj.define_singleton_method(:trained_skills) { [] }
    obj.define_singleton_method(:max_mana) { 4 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { "Tier #{tier}" }
    obj.define_singleton_method(:granted_abilities) { [] }
    obj
  end

  def weapon(enchantment)
    { item_type: 'Long sword', display_name: '+2 Sword', ranged: false, natural: false, speed: 2,
      damage_types: ['Slashing'], threshold: 5, bleed: 7, damage_formula: 'str / 4',
      enhancement: 2, enchantment: enchantment }
  end

  def setup_fight(target_tier:, enchantment:)
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    allow(Creatures).to receive(:lookup) { |cid| creature(cid.to_s == '1' ? 1 : target_tier) }
    allow_any_instance_of(Sinatra::Application).to receive(:equipped_weapons) { |_app, cid| cid.to_s == '1' ? [weapon(enchantment)] : [] }
    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'c.json'))
    Encounter.state = Encounter::State.new({}, data_path: File.join(tmp, 'e.json'),
                                           creature_lookup: ->(id) { creature(id.to_s == '1' ? 1 : target_tier) },
                                           conditions_for: ->(cid) { Conditions.store.instance_for(cid) })
    @atk = Encounter.state.add_combatant('1')
    @tgt = Encounter.state.add_combatant('2')
    header 'Host', 'localhost'
    get "/encounter/attack_builder?attacker_id=#{@atk[:id]}"
    JSON.parse(CGI.unescapeHTML(last_response.body.match(/data-builder="([^"]*)"/)[1]))
  end

  def enchant_patch(blob)
    defense = blob['steps'].find { |s| s['key'] == 'defense' }
    opt = defense['options_map']["#{@tgt[:id]}|Long sword"].find { |o| o['value'] == 'none' }
    {
      dice: opt.dig('patch', 'set_dice').find { |d| d['id'] == 'enchant' }['count'],
      excluded: opt.dig('patch', 'set_excluded').find { |d| d['id'] == 'enchant' }['excluded'],
      name: opt.dig('patch', 'set_name').find { |d| d['id'] == 'enchant' }['roll_name'],
      no_cross: opt.dig('patch', 'set_no_propagate').find { |d| d['id'] == 'enchant' }['types']
    }
  end

  it 'adds X flavored dice for a +2 Flaming weapon, kept from crossing to the defender' do
    blob = setup_fight(target_tier: 1, enchantment: { label: 'Flaming', damage_type: 'fire', multiplier: 1 })
    expect(blob['rolls'].map { |r| r['id'] }).to include('enchant')
    e = enchant_patch(blob)
    expect(e).to include(dice: 2, excluded: false, name: 'Flaming dice')
    expect(e[:no_cross]).to include('Competency', 'Guidance')
  end

  it "puts the weapon's +X Guidance on the attack" do
    blob = setup_fight(target_tier: 1, enchantment: nil)
    action = blob['steps'].find { |s| s['key'] == 'action' }
    bpl = action['options'].find { |o| o['patch'] }.dig('patch', 'set_bpl').first['bonus_penalty_list']
    expect(bpl).to include(['Guidance', 2])
    expect(enchant_patch(blob)).to include(dice: 2, name: '+2 dice')
  end

  it 'rolls no Glorious dice against a target of the same Tier' do
    glory = { label: 'Glorious', damage_type: 'slashing', multiplier: 2, only_vs_higher_tier: true }
    expect(enchant_patch(setup_fight(target_tier: 1, enchantment: glory))).to include(dice: 0, excluded: true)
  end

  it 'rolls Glorious dice against a higher-Tier target' do
    glory = { label: 'Glorious', damage_type: 'slashing', multiplier: 2, only_vs_higher_tier: true }
    expect(enchant_patch(setup_fight(target_tier: 2, enchantment: glory))).to include(dice: 2, excluded: false)
  end

  it 'a Divine Favor makes the weapon Radiant at the higher of its Tier and the weapon\'s +X' do
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    allow(Creatures).to receive(:lookup) { |_cid| creature(1) }
    allow_any_instance_of(Sinatra::Application).to receive(:equipped_weapons) { |_app, cid| cid.to_s == '1' ? [weapon(nil)] : [] }
    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'c.json'))
    Encounter.state = Encounter::State.new({}, data_path: File.join(tmp, 'e.json'),
                                           creature_lookup: ->(_id) { creature(1) },
                                           conditions_for: ->(cid) { Conditions.store.instance_for(cid) })
    @atk = Encounter.state.add_combatant('1')
    @tgt = Encounter.state.add_combatant('2')
    header 'Host', 'localhost'
    Conditions.store.instance_for('1').apply_effect('target_key' => 'radiant_weapon', 'bonus_type' => 'Guidance',
                                                    'amount' => 3, 'source_id' => 'spell:Improved Divine Favor')
    get "/encounter/attack_builder?attacker_id=#{@atk[:id]}"
    blob = JSON.parse(CGI.unescapeHTML(last_response.body.match(/data-builder="([^"]*)"/)[1]))
    expect(enchant_patch(blob)).to include(dice: 3, name: 'Radiant dice')
  end

  it "a Glorious Weapon blessing rolls its dice only against a higher-Tier target" do
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    allow(Creatures).to receive(:lookup) { |cid| creature(cid.to_s == '1' ? 1 : 1) }
    allow_any_instance_of(Sinatra::Application).to receive(:equipped_weapons) { |_app, cid| cid.to_s == '1' ? [weapon(nil)] : [] }
    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'c.json'))
    Encounter.state = Encounter::State.new({}, data_path: File.join(tmp, 'e.json'),
                                           creature_lookup: ->(_id) { creature(1) },
                                           conditions_for: ->(cid) { Conditions.store.instance_for(cid) })
    @atk = Encounter.state.add_combatant('1')
    @tgt = Encounter.state.add_combatant('2')
    header 'Host', 'localhost'
    Conditions.store.instance_for('1').apply_effect('target_key' => 'glorious_weapon', 'bonus_type' => 'Guidance',
                                                    'amount' => 1, 'source_id' => 'spell:Lesser Glorious Weapon')
    get "/encounter/attack_builder?attacker_id=#{@atk[:id]}"
    blob = JSON.parse(CGI.unescapeHTML(last_response.body.match(/data-builder="([^"]*)"/)[1]))
    expect(enchant_patch(blob)).to include(dice: 0, excluded: true, name: 'Glorious dice') # same Tier
  end
end
