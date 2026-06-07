require 'spec_helper'
require 'device_registry'
require 'tmpdir'
require 'json'

RSpec.describe DeviceRegistry do
  let(:tmpdir)    { Dir.mktmpdir('device-registry') }
  let(:data_path) { File.join(tmpdir, 'devices.json') }

  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def registry
    DeviceRegistry.new(data_path)
  end

  describe 'a fresh registry' do
    it 'starts empty — no rows until a real device connects' do
      expect(registry.list).to eq([])
    end

    it 'does not write a file until something is recorded' do
      registry
      expect(File.exist?(data_path)).to be(false)
    end

    it 'records a device with a nil assignment and a last_seen stamp' do
      d = registry.touch('abc')
      expect(d['character_id']).to be_nil
      expect(d['last_seen']).to match(/\A\d{4}-\d\d-\d\dT/)
    end
  end

  describe '#touch' do
    it 'creates a record the first time a device is seen' do
      r = registry
      expect(r.find('abc')).to be_nil
      rec = r.touch('abc')
      expect(rec['device_id']).to eq('abc')
      expect(r.find('abc')).not_to be_nil
    end

    it 'updates last_seen on a returning device without duplicating it' do
      r = registry
      r.touch('abc')
      first = r.find('abc')['last_seen']
      sleep 0.01
      allow(Time).to receive(:now).and_return(Time.now + 60)
      r.touch('abc')
      expect(r.list.map { |d| d['device_id'] }.count('abc')).to eq(1)
      expect(r.find('abc')['last_seen']).not_to eq(first)
    end
  end

  describe '#assign_character / #unassign_character' do
    it 'stores the assignment as an integer and reports it back' do
      r = registry
      r.touch('abc')
      r.assign_character('abc', '7')
      expect(r.character_id_for('abc')).to eq(7)
    end

    it 'creates the device when assigning one that has not been seen' do
      r = registry
      r.assign_character('never-seen', 3)
      expect(r.character_id_for('never-seen')).to eq(3)
    end

    it 'clears the assignment on unassign' do
      r = registry
      r.assign_character('abc', 7)
      r.unassign_character('abc')
      expect(r.character_id_for('abc')).to be_nil
    end

    it 'persists assignments across reloads' do
      registry.tap { |r| r.touch('abc'); r.assign_character('abc', 5) }
      expect(DeviceRegistry.new(data_path).character_id_for('abc')).to eq(5)
    end
  end

  describe '#list ordering' do
    it 'returns the most recently seen devices first' do
      r = registry
      base = Time.now
      allow(Time).to receive(:now).and_return(base)
      r.touch('old')
      allow(Time).to receive(:now).and_return(base + 120)
      r.touch('new')
      expect(r.list.first['device_id']).to eq('new')
    end

    it 'returns defensive copies that do not mutate the store' do
      r = registry
      r.touch('abc')
      r.list.find { |d| d['device_id'] == 'abc' }['character_id'] = 99
      expect(r.character_id_for('abc')).to be_nil
    end
  end

  describe 'malformed data' do
    it 'recovers from a non-array / corrupt JSON file as an empty registry' do
      File.write(data_path, 'not json at all')
      expect(registry.list).to eq([])
    end
  end
end
