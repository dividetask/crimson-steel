require 'spec_helper'
require 'rack/test'
require 'json'
require 'cgi'
require 'tmpdir'
require_relative '../../app'

# Regression for the Cast Builder seam: Spiritual Weapon is an auto-channel
# Spell that fills a persistent Reservoir, but it ALSO carries `attack_roll: true`
# — casting it is an opposed strike against a target. The builder must therefore
# mark the cast as one that rolls (so the Cast pane rolls the casting check and
# offers the defender its defence) while still pouring the cast dice into the
# Reservoir. A regression that suppressed the roll for any Reservoir-filling
# Spell would silently turn the cast into a no-roll pour.
RSpec.describe 'GET /encounter/cast_builder — Spiritual Weapon', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('cast-builder-sw') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  # A caster who knows Spiritual Weapon (a Tier-2 War-domain Spell).
  def creature
    obj = Object.new
    obj.define_singleton_method(:tier) { 2 }
    obj.define_singleton_method(:attribute_value) { |_a| 14 }
    obj.define_singleton_method(:ranks_for) { |_k| 4 }
    obj.define_singleton_method(:trained_skills) { [] }
    obj.define_singleton_method(:max_mana) { 8 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:tags) { ['player_character'] }
    obj.define_singleton_method(:name) { 'Cleric' }
    obj.define_singleton_method(:granted_abilities) do
      [{ name: 'Spiritual Weapon', source: 'class:cleric' }]
    end
    obj
  end

  before do
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
    allow(Creatures).to receive(:lookup).and_return(creature)

    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'conditions.json'))
    cond = Conditions::Instance.new
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'encounter.json'),
      creature_lookup: ->(_id) { creature }, conditions_for: ->(_id) { cond }
    )
    @caster = Encounter.state.add_combatant('1')
  end

  # Pull the embedded Action Builder blob (data-builder="<escaped JSON>") out of
  # the rendered builder fragment.
  def builder_blob(body)
    m = body.match(/data-builder="([^"]*)"/) or raise "no data-builder in:\n#{body}"
    JSON.parse(CGI.unescapeHTML(m[1]))
  end

  it 'marks the Spiritual Weapon cast as one that rolls (and fills a Reservoir)' do
    header 'Host', 'localhost'
    get "/encounter/cast_builder?caster_id=#{@caster[:id]}"
    expect(last_response.status).to eq(200)

    blob = builder_blob(last_response.body)
    spell_step = blob['steps'].find { |s| s['key'] == 'spell' }
    sw = Array(spell_step['options']).find { |o| o['spell_name'] == 'Spiritual Weapon' }
    expect(sw).not_to be_nil, 'Spiritual Weapon was not offered in the Cast list'

    # The cast both rolls (attack roll) and fills its Reservoir.
    expect(sw.dig('cast', 'roll')).to be(true)
    expect(sw.dig('cast', 'reservoir')).to be(true)
  end
end
