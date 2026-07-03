require 'spec_helper'
require 'scene_round'
require 'tmpdir'

# The Scene Round tracker is the DM Page's out-of-combat "Round like Combat"
# counter, persisted so the count survives a server restart.
RSpec.describe SceneRound::Store do
  around do |ex|
    Dir.mktmpdir { |dir| @path = File.join(dir, 'scene_round.json'); ex.run }
  end

  def store
    SceneRound::Store.load(data_path: @path)
  end

  it 'starts at Round 1' do
    expect(store.round).to eq(1)
  end

  it 'advances one Round at a time' do
    s = store
    expect(s.next!).to eq(2)
    expect(s.next!).to eq(3)
    expect(s.round).to eq(3)
  end

  it 'persists the count across reloads' do
    store.next!
    store.next!
    expect(store.round).to eq(3)
  end

  it 'resets back to Round 1' do
    s = store
    s.next!
    s.next!
    expect(s.reset!).to eq(1)
    expect(store.round).to eq(1)
  end

  it 'clamps a corrupt or below-one persisted value up to 1' do
    File.write(@path, JSON.generate('round' => 0))
    expect(store.round).to eq(1)
  end
end
