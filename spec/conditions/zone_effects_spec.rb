require 'spec_helper'
require 'tmpdir'

# Conditions Zone Effects (conditions_design.md → Zone Effect): module-level
# spatial Effects paired with an Atlas Zone by a shared source_id.
RSpec.describe 'Conditions::Store zone effects' do
  let(:tmpdir) { Dir.mktmpdir('conditions-zones') }
  let(:data_path) { File.join(tmpdir, 'conditions_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def store(raw = {})
    Conditions::Store.new(raw, data_path: data_path)
  end

  it 'creates a Zone Effect with its Atlas pairing and triggers' do
    s = store
    rec = s.create_zone_effect(
      source_id: 'cast:mist:7', atlas_zone_id: 12,
      triggers: { on_enter: [{ 'attribute' => 'dex', 'fail' => 'prone' }] },
      ends_on_round: 9
    )
    expect(rec[:source_id]).to eq('cast:mist:7')
    expect(rec[:atlas_zone_id]).to eq(12)
    expect(rec[:triggers][:on_enter]).to eq([{ 'attribute' => 'dex', 'fail' => 'prone' }])
    expect(rec[:ends_on_round]).to eq(9)
    expect(s.zone_effect(source_id: 'cast:mist:7')).to eq(rec)
  end

  it 'replaces a Zone Effect with the same source_id rather than duplicating' do
    s = store
    s.create_zone_effect(source_id: 'cast:mist:7', atlas_zone_id: 1)
    s.create_zone_effect(source_id: 'cast:mist:7', atlas_zone_id: 2)
    expect(s.list_zone_effects.length).to eq(1)
    expect(s.zone_effect(source_id: 'cast:mist:7')[:atlas_zone_id]).to eq(2)
  end

  it 'removes a Zone Effect by source_id' do
    s = store
    s.create_zone_effect(source_id: 'cast:mist:7', atlas_zone_id: 1)
    removed = s.remove_zone_effect(source_id: 'cast:mist:7')
    expect(removed[:atlas_zone_id]).to eq(1)
    expect(s.list_zone_effects).to be_empty
    expect(s.remove_zone_effect(source_id: 'nope')).to be_nil
  end

  it 'filters expired Zone Effects by current_round; null ends_on_round never expires' do
    s = store
    s.create_zone_effect(source_id: 'timed', atlas_zone_id: 1, ends_on_round: 5)
    s.create_zone_effect(source_id: 'forever', atlas_zone_id: 2, ends_on_round: nil)
    expect(s.list_zone_effects(current_round: 4).map { |z| z[:source_id] }).to contain_exactly('timed', 'forever')
    expect(s.list_zone_effects(current_round: 5).map { |z| z[:source_id] }).to contain_exactly('forever')

    expired = s.clear_expired_zone_effects(5)
    expect(expired.map { |z| z[:source_id] }).to eq(['timed'])
    expect(s.list_zone_effects.map { |z| z[:source_id] }).to eq(['forever'])
  end

  it 'round-trips Zone Effects through to_h and reload' do
    s = store
    s.create_zone_effect(source_id: 'cast:web:3', atlas_zone_id: 4,
                         triggers: { on_enter: [{ 'attribute' => 'dex', 'fail' => 'restrained' }] },
                         ends_on_round: 12)
    reloaded = store(JSON.parse(JSON.generate(s.to_h)))
    rec = reloaded.zone_effect(source_id: 'cast:web:3')
    expect(rec[:atlas_zone_id]).to eq(4)
    expect(rec[:ends_on_round]).to eq(12)
    expect(rec[:triggers][:on_enter]).to eq([{ 'attribute' => 'dex', 'fail' => 'restrained' }])
  end

  it 'omits zone_effects from the serialized form when there are none' do
    expect(store.to_h).not_to have_key('zone_effects')
  end
end
