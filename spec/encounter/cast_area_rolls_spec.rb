require 'spec_helper'
require 'rack/test'
require 'tmpdir'
require_relative '../../app'

# Coverage for GET /encounter/cast_area_rolls — the per-creature Save Rolls the
# cast builder fetches for a spread cast (an area footprint OR a multi-target
# toggle selection). Each caught creature must roll its own Saving Throw at its
# real Dice Cap.
#
# Regression: the endpoint resolved the Spell with a bare `Abilities.lookup`,
# which only knows base catalog keys. A cast launched under a Variant name
# (e.g. "Create Illusionary Sound", a Variant of "Create Illusion") resolved to
# nil, dropped the `save`, and seeded every caught creature at zero Save dice —
# so everyone but the caster showed "0 dice to roll for their save".
RSpec.describe 'GET /encounter/cast_area_rolls — spread Save Rolls', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  let(:tmp) { Dir.mktmpdir('cast-area-rolls') }
  after { FileUtils.remove_entry(tmp) if File.exist?(tmp) }

  before do
    # The DM is identified by a loopback request; emulate that here.
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)

    Conditions.store = Conditions::Store.new({}, data_path: File.join(tmp, 'conditions.json'))
    cond = Conditions::Instance.new
    Encounter.state = Encounter::State.new(
      {}, data_path: File.join(tmp, 'encounter.json'),
      creature_lookup: ->(id) { Creatures.lookup(id) }, conditions_for: ->(_id) { cond }
    )
    # Lysander (3) casts; Olga (2) and an Orc Handler (109) are caught targets.
    @caster = Encounter.state.add_combatant('3')
    @olga   = Encounter.state.add_combatant('2')
    @orc    = Encounter.state.add_combatant('109')
  end

  # The dice count for a caught creature's Save Row, parsed out of the rendered
  # roll stub ("<n> dice @ TN ...") for that creature's `save-<id>` group.
  def save_dice_for(body, combatant_id)
    row = body[/data-roll-id="save-#{combatant_id}".*?<\/tbody>/m]
    row && row[/(\d+) dice @ TN/, 1]&.to_i
  end

  it 'seeds each caught creature at its real Intelligence Save Dice Cap for a Variant-named Spell' do
    header 'Host', 'localhost'
    get '/encounter/cast_area_rolls', { caster_id: @caster[:id], spell: 'Create Illusionary Sound',
                                        'affected' => [@olga[:id].to_s, @orc[:id].to_s] },
        'REMOTE_ADDR' => '127.0.0.1'

    expect(last_response.status).to eq(200)
    body = last_response.body
    # Both caught creatures roll an Intelligence save at a non-zero Dice Cap —
    # the heart of the bug was these coming back as zero.
    expect(body).to include('Intelligence save')
    expect(save_dice_for(body, @olga[:id])).to be > 0
    expect(save_dice_for(body, @orc[:id])).to be > 0
  end
end
