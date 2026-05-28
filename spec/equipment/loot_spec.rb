require_relative 'support'

RSpec.describe 'Roll Loot Table' do
  let(:catalog) { Equipment::Catalog.load }

  def build(tables: {}, option_lists: {}, rng: SequenceRng.new)
    loot = Equipment::LootTables.new(tables: tables, option_lists: option_lists)
    Equipment::Instance.new(catalog: catalog, loot: loot, rng: rng)
  end

  describe 'Row shapes' do
    it 'Guaranteed row always produces its payload' do
      inst = build(tables: { 'g' => { 'rolls' => [{ 'item' => { 'item' => 'Long sword' } }] } })
      out = inst.roll_loot_table('g')
      expect(out.map(&:item_type)).to eq(['Long sword'])
    end

    it 'Independent Chance respects the probability' do
      table = { 'g' => { 'rolls' => [{ 'chance' => 0.5, 'item' => { 'item' => 'Long sword' } }] } }
      drops = build(tables: table, rng: SequenceRng.new([0.4])).roll_loot_table('g')
      misses = build(tables: table, rng: SequenceRng.new([0.6])).roll_loot_table('g')
      expect(drops.size).to eq(1)
      expect(misses).to be_empty
    end

    it 'Weighted Choice picks the first cumulative bucket above u' do
      table = { 'g' => { 'rolls' => [{ 'options' => [
        { 'chance' => 0.3, 'item' => { 'item' => 'A' } },
        { 'chance' => 0.5, 'item' => { 'item' => 'B' } }
      ] }] } }
      a = build(tables: table, rng: SequenceRng.new([0.2])).roll_loot_table('g')
      b = build(tables: table, rng: SequenceRng.new([0.5])).roll_loot_table('g')
      none = build(tables: table, rng: SequenceRng.new([0.9])).roll_loot_table('g')
      expect(a.map(&:item_type)).to eq(['A'])
      expect(b.map(&:item_type)).to eq(['B'])
      expect(none).to be_empty
    end

    it 'Gated Weighted Choice rolls chance first' do
      table = { 'g' => { 'rolls' => [{ 'chance' => 0.5, 'options' => [
        { 'chance' => 1.0, 'item' => { 'item' => 'A' } }
      ] }] } }
      hit = build(tables: table, rng: SequenceRng.new([0.4, 0.0])).roll_loot_table('g')
      miss = build(tables: table, rng: SequenceRng.new([0.6])).roll_loot_table('g')
      expect(hit.map(&:item_type)).to eq(['A'])
      expect(miss).to be_empty
    end

    it 'plural items: produces multiple Stacks' do
      table = { 'g' => { 'rolls' => [{ 'items' => [
        { 'item' => 'Shortbow' }, { 'item' => 'Arrow', 'quantity' => 20 }
      ] }] } }
      out = build(tables: table).roll_loot_table('g')
      expect(out.map { |s| [s.item_type, s.quantity] }).to eq([['Shortbow', 1], ['Arrow', 20]])
    end

    it 'row-level equipped: true propagates to every produced Stack' do
      table = { 'g' => { 'rolls' => [{ 'equipped' => true, 'items' => [
        { 'item' => 'Rapier' }, { 'item' => 'Studded leather' }
      ] }] } }
      out = build(tables: table).roll_loot_table('g')
      expect(out.map(&:equipped)).to eq([true, true])
    end

    it 'evaluates a Dice Expression quantity per roll' do
      table = { 'g' => { 'rolls' => [{ 'item' => { 'item' => 'Gold', 'quantity' => '2d6 + 3' } }] } }
      out = build(tables: table, rng: SequenceRng.new([0.0, 0.0])).roll_loot_table('g')
      expect(out[0].quantity).to eq(5)
    end
  end

  describe 'Roll Variables' do
    def guard_table(options)
      { 'g' => { 'rolls' => [
        { 'as' => 'hand', 'options' => options },
        { 'when' => { 'hand' => 'one_handed' }, 'item' => { 'item' => 'Light wooden shield' } }
      ] } }
    end

    let(:options) do
      [{ 'chance' => 0.5, 'key' => 'one_handed', 'item' => { 'item' => 'Short sword' } },
       { 'chance' => 0.5, 'key' => 'two_handed', 'item' => { 'item' => 'Spear' } }]
    end

    it 'when against a matching variable allows the row' do
      out = build(tables: guard_table(options), rng: SequenceRng.new([0.2])).roll_loot_table('g')
      expect(out.map(&:item_type)).to eq(['Short sword', 'Light wooden shield'])
    end

    it 'when against a non-matching variable skips the row' do
      out = build(tables: guard_table(options), rng: SequenceRng.new([0.7])).roll_loot_table('g')
      expect(out.map(&:item_type)).to eq(['Spear'])
    end

    it 'when against an unset variable compares to null' do
      skips = { 'g' => { 'rolls' => [{ 'when' => { 'hand' => 'one_handed' }, 'item' => { 'item' => 'A' } }] } }
      allows = { 'g' => { 'rolls' => [{ 'when' => { 'hand' => nil }, 'item' => { 'item' => 'A' } }] } }
      expect(build(tables: skips).roll_loot_table('g')).to be_empty
      expect(build(tables: allows).roll_loot_table('g').size).to eq(1)
    end

    it 'a skipped row does not publish' do
      table = { 'g' => { 'rolls' => [
        { 'when' => { 'hand' => 'one_handed' }, 'as' => 'hand', 'key' => 'published',
          'item' => { 'item' => 'A' } },
        { 'when' => { 'hand' => 'published' }, 'item' => { 'item' => 'B' } }
      ] } }
      expect(build(tables: table).roll_loot_table('g')).to be_empty
    end

    it 'scopes variables to one roll' do
      inst = build(tables: guard_table(options), rng: SequenceRng.new([0.2, 0.7]))
      first = inst.roll_loot_table('g')
      second = inst.roll_loot_table('g')
      expect(first.map(&:item_type)).to eq(['Short sword', 'Light wooden shield'])
      expect(second.map(&:item_type)).to eq(['Spear'])
    end
  end

  describe 'Option Lists' do
    it 'substitutes a named Option List for inline options' do
      lists = { 'magic' => [{ 'chance' => 1.0, 'key' => 'k', 'item' => { 'item' => 'Rapier' } }] }
      table = { 'g' => { 'rolls' => [{ 'options' => 'magic' }] } }
      out = build(tables: table, option_lists: lists).roll_loot_table('g')
      expect(out.map(&:item_type)).to eq(['Rapier'])
    end

    it 'follows a recursive from: chain' do
      lists = {
        'outer' => [{ 'chance' => 1.0, 'from' => 'inner' }],
        'inner' => [{ 'chance' => 1.0, 'key' => 'k', 'item' => { 'item' => 'Dagger' } }]
      }
      table = { 'g' => { 'rolls' => [{ 'options' => 'outer' }] } }
      out = build(tables: table, option_lists: lists, rng: SequenceRng.new([0.0, 0.0])).roll_loot_table('g')
      expect(out.map(&:item_type)).to eq(['Dagger'])
    end
  end

  it 'returns an error sentinel for an unknown table' do
    expect(build.roll_loot_table('nope')).to be(Equipment::ERROR)
  end
end
