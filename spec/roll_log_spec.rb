require 'spec_helper'
require 'roll_log'
require 'tmpdir'

# The Roll Log records every player Skill Roll (the compact roll stub POSTs
# here) so the DM sees each roll and its history on the Log page.
RSpec.describe RollLog::Store do
  around do |ex|
    Dir.mktmpdir { |dir| @path = File.join(dir, 'roll_log.json'); ex.run }
  end

  def store
    RollLog::Store.load(data_path: @path)
  end

  it 'appends rolls, assigning increasing ids, and lists them newest first' do
    s = store
    s.add('creature_name' => 'Bryn', 'roll_name' => 'Stealth check', 'tn' => 5,
          'dice_count' => 4, 'dice' => [10, 3, 6, 1], 'dois' => 2, 'critical_count' => 1, 'at' => 100)
    s.add('creature_name' => 'Veyl', 'roll_name' => 'Arcana check', 'tn' => 4,
          'dice_count' => 3, 'dice' => [2, 4, 8], 'dois' => 2, 'critical_count' => 0, 'at' => 200)
    recent = s.recent
    expect(recent.map { |e| e['creature_name'] }).to eq(%w[Veyl Bryn])
    expect(recent.map { |e| e['id'] }).to eq([2, 1])
  end

  it 'persists across reloads' do
    store.add('creature_name' => 'Bryn', 'roll_name' => 'Stealth check', 'tn' => 5,
              'dice_count' => 4, 'dice' => [10, 3, 6, 1], 'dois' => 2, 'critical_count' => 1, 'at' => 100)
    reloaded = store
    expect(reloaded.recent.length).to eq(1)
    expect(reloaded.recent.first['dice']).to eq([10, 3, 6, 1])
  end

  it 'normalizes posted values to their expected types' do
    entry = store.add('creature_name' => 'Bryn', 'roll_name' => 'Stealth check',
                      'ranks' => '3', 'tn' => '5', 'base_tn' => '8',
                      'bonus_penalty_list' => [['Competency', '2'], ['Guidance', 1]],
                      'dice_count' => '4', 'starting_value' => '1',
                      'dice' => %w[10 3 6 1], 'dois' => '2', 'critical_count' => '1', 'at' => '123')
    expect(entry['ranks']).to eq(3)
    expect(entry['tn']).to eq(5)
    expect(entry['base_tn']).to eq(8)
    expect(entry['bonus_penalty_list']).to eq([['Competency', 2], ['Guidance', 1]])
    expect(entry['starting_value']).to eq(1)
    expect(entry['dice']).to eq([10, 3, 6, 1])
    expect(entry['critical_count']).to eq(1)
    expect(entry['at']).to eq(123)
  end

  it 'keeps base_tn nil and bpl empty when the TN breakdown was not supplied' do
    entry = store.add('creature_name' => 'Bryn', 'roll_name' => 'check', 'tn' => 5,
                      'dice_count' => 1, 'dice' => [7], 'dois' => 1, 'critical_count' => 0, 'at' => 1)
    expect(entry['base_tn']).to be_nil
    expect(entry['bonus_penalty_list']).to eq([])
  end

  it 'caps the log at MAX_ENTRIES, keeping the newest' do
    s = store
    (1..(RollLog::Store::MAX_ENTRIES + 5)).each do |i|
      s.add('creature_name' => "PC#{i}", 'roll_name' => 'check', 'tn' => 5,
            'dice_count' => 1, 'dice' => [i % 10 + 1], 'dois' => 0, 'critical_count' => 0, 'at' => i)
    end
    recent = s.recent
    expect(recent.length).to eq(RollLog::Store::MAX_ENTRIES)
    # The newest (highest id) survives; the oldest are dropped.
    expect(recent.first['creature_name']).to eq("PC#{RollLog::Store::MAX_ENTRIES + 5}")
  end

  it 'clears the log' do
    s = store
    s.add('creature_name' => 'Bryn', 'roll_name' => 'check', 'tn' => 5, 'dice_count' => 1,
          'dice' => [7], 'dois' => 1, 'critical_count' => 0, 'at' => 1)
    s.clear!
    expect(store.recent).to be_empty
  end
end
