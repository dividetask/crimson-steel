require_relative '../lib/modifiers'

RSpec.describe Modifiers do
  describe '#total_for' do
    it 'sums untyped modifiers freely' do
      m = Modifiers.new([
        { 'target' => 'speed', 'add' => 5 },
        { 'target' => 'speed', 'add' => 10 }
      ])
      expect(m.total_for('speed')).to eq(15)
    end

    it 'collapses same-typed bonuses to the highest positive' do
      m = Modifiers.new([
        { 'target' => 'skill.persuasion', 'type' => 'Inherent', 'add' => 1 },
        { 'target' => 'skill.persuasion', 'type' => 'Inherent', 'add' => 3 }
      ])
      expect(m.total_for('skill.persuasion')).to eq(3)
    end

    it 'collapses same-typed penalties to the most negative' do
      m = Modifiers.new([
        { 'target' => 'attribute.dex', 'type' => 'Morale', 'add' => -1 },
        { 'target' => 'attribute.dex', 'type' => 'Morale', 'add' => -3 }
      ])
      expect(m.total_for('attribute.dex')).to eq(-3)
    end

    it 'allows opposing-polarity modifiers within a single type to net out' do
      m = Modifiers.new([
        { 'target' => 'attribute.dex', 'type' => 'Morale', 'add' => 2 },
        { 'target' => 'attribute.dex', 'type' => 'Morale', 'add' => -1 }
      ])
      expect(m.total_for('attribute.dex')).to eq(1)
    end

    it 'sums different bonus types separately' do
      m = Modifiers.new([
        { 'target' => 'skill.persuasion', 'type' => 'Inherent',  'add' => 1 },
        { 'target' => 'skill.persuasion', 'type' => 'Competency', 'add' => 2 }
      ])
      expect(m.total_for('skill.persuasion')).to eq(3)
    end

    it 'ignores modifiers whose target does not match' do
      m = Modifiers.new([{ 'target' => 'speed', 'add' => 10 }])
      expect(m.total_for('damage_resilience')).to eq(0)
    end

    context 'with descriptors' do
      let(:set) do
        Modifiers.new([
          { 'target' => 'save.con', 'type' => 'Inherent', 'add' => 1 },
          { 'target' => 'save.con', 'type' => 'Inherent', 'add' => 2, 'descriptors' => ['poison'] },
          { 'target' => 'save.con', 'type' => 'Inherent', 'add' => 3, 'descriptors' => %w[poison disease] }
        ])
      end

      it 'returns only undescribed modifiers when no descriptors are supplied' do
        expect(set.total_for('save.con')).to eq(1)
      end

      it 'includes descriptor-tagged modifiers whose tags are a subset of the query' do
        # Inherent: max of [1, 2] = 2 (the poison-only entry); the
        # poison+disease entry has 'disease' which isn't requested.
        expect(set.total_for('save.con', descriptors: [:poison])).to eq(2)
      end

      it 'fires multi-descriptor modifiers when every descriptor is present' do
        # Inherent: max of [1, 2, 3] = 3 (poison+disease entry now applies).
        expect(set.total_for('save.con', descriptors: %i[poison disease])).to eq(3)
      end
    end
  end
end
