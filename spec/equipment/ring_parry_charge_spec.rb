require_relative 'support'

# Per-day item charges are tracked generically on the Stack as `daily_charges`
# (keyed by feature, e.g. 'parry'): each key records the day_index it was last
# used and how many times that day. The cap (uses per day) lives in the catalog
# (`uses_per_day`); recharge is implicit — a use stamped on an earlier day reads
# as zero today. A Ring of Parry is the first consumer (1/day).
RSpec.describe 'Daily item charges (Ring of Parry, generalized)' do
  let(:catalog)    { Equipment::Catalog.load }
  let(:accessor)   { FakeCreatureAccessor.new }
  let(:conditions) { RecordingConditions.new }
  let(:inst) do
    Equipment::Instance.new(catalog: catalog, creature_accessor: accessor, conditions: conditions)
  end

  def ring_stack
    accessor.set_inventory('2', [Equipment::Stack.normalize(item: 'Ring of Parry', equipped: true)])
    inst.get_inventory('creature:2').first
  end

  describe 'Stack#daily_uses / #record_daily_use' do
    it 'counts uses spent on a day and recharges when the day rolls over' do
      s = Equipment::Stack.normalize(item: 'Ring of Parry')
      expect(s.daily_uses('parry', 3)).to eq(0)

      s.record_daily_use('parry', 3)
      expect(s.daily_uses('parry', 3)).to eq(1)
      s.record_daily_use('parry', 3)
      expect(s.daily_uses('parry', 3)).to eq(2)        # supports N/day

      # A later day reads as recharged (0 used).
      expect(s.daily_uses('parry', 4)).to eq(0)
    end

    it 'tracks distinct feature keys independently' do
      s = Equipment::Stack.normalize(item: 'Ring of Parry')
      s.record_daily_use('parry', 1)
      expect(s.daily_uses('parry', 1)).to eq(1)
      expect(s.daily_uses('smite', 1)).to eq(0)
    end
  end

  describe 'Instance#spend_daily_charge! / #daily_charge_remaining' do
    it 'spends a charge against the per-day cap and persists it' do
      s = ring_stack
      cap = (catalog.definition_of('Ring of Parry') || {})['uses_per_day']
      expect(cap).to eq(1)
      expect(inst.daily_charge_remaining(s, 'parry', cap, 0)).to eq(1)

      inst.spend_daily_charge!('creature:2', 0, 'parry', 0)
      again = inst.get_inventory('creature:2').first
      expect(inst.daily_charge_remaining(again, 'parry', cap, 0)).to eq(0)   # spent today
      expect(inst.daily_charge_remaining(again, 'parry', cap, 1)).to eq(1)   # recharged next day
    end
  end

  describe 'serialization' do
    it 'round-trips daily_charges through Stack#to_h / normalize' do
      s = Equipment::Stack.normalize(item: 'Ring of Parry')
      s.record_daily_use('parry', 5)
      h = s.to_h
      expect(h['daily_charges']).to eq('parry' => { 'day' => 5, 'used' => 1 })
      expect(Equipment::Stack.normalize(h).daily_uses('parry', 5)).to eq(1)
      # Omitted when there are no charges.
      expect(Equipment::Stack.normalize(item: 'Ring of Parry').to_h).not_to have_key('daily_charges')
    end

    it 'migrates the legacy parry_used_day field onto daily_charges' do
      s = Equipment::Stack.normalize(item: 'Ring of Parry', parry_used_day: 7)
      expect(s.daily_uses('parry', 7)).to eq(1)
      expect(s.daily_uses('parry', 8)).to eq(0)
      expect(s.to_h).not_to have_key('parry_used_day')
    end
  end
end
