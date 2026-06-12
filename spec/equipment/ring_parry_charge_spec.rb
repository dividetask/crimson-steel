require_relative 'support'

# A Ring of Parry's once-per-day charge is stored on the Stack as the day_index
# it was last spent (`parry_used_day`), persisted via set_parry_used_day, and
# round-trips through Stack serialization.
RSpec.describe 'Ring of Parry — daily charge persistence' do
  let(:catalog)    { Equipment::Catalog.load }
  let(:accessor)   { FakeCreatureAccessor.new }
  let(:conditions) { RecordingConditions.new }
  let(:inst) do
    Equipment::Instance.new(catalog: catalog, creature_accessor: accessor, conditions: conditions)
  end

  it 'stamps and persists the day the charge was spent, and recharges with nil' do
    accessor.set_inventory('2', [Equipment::Stack.normalize(item: 'Ring of Parry', equipped: true)])
    expect(inst.get_inventory('creature:2').first.parry_used_day).to be_nil

    inst.set_parry_used_day('creature:2', 0, 3)
    expect(inst.get_inventory('creature:2').first.parry_used_day).to eq(3)

    # nil recharges it.
    inst.set_parry_used_day('creature:2', 0, nil)
    expect(inst.get_inventory('creature:2').first.parry_used_day).to be_nil
  end

  it 'round-trips parry_used_day through Stack#to_h / normalize' do
    s = Equipment::Stack.normalize(item: 'Ring of Parry', equipped: true, parry_used_day: 5)
    expect(s.parry_used_day).to eq(5)
    expect(s.to_h['parry_used_day']).to eq(5)
    expect(Equipment::Stack.normalize(s.to_h).parry_used_day).to eq(5)
    # Omitted from the serialized form when unspent (default nil).
    expect(Equipment::Stack.normalize(item: 'Ring of Parry').to_h).not_to have_key('parry_used_day')
  end
end
