require_relative 'support'

# Roll Tables (roll_tables.yaml): a named die-table an Ability fires on
# via its `roll_table:` field. Exercised against the shipped catalog plus
# a few inline validation cases.
RSpec.describe 'Abilities roll tables' do
  describe 'the shipped Kesser Reversal Table' do
    let(:table) { Abilities.roll_table('Kesser Reversal Table') }

    it 'loads a d10 table with one entry per face' do
      expect(table['die']).to eq(10)
      expect(table['entries'].keys.sort).to eq((1..10).to_a)
    end

    it 'carries a name and effect per entry' do
      expect(table['entries'][1]['name']).to eq('Disaster')
      expect(table['entries'][10]['name']).to eq('Crit')
      expect(table['entries'][4]['effect']).to include('free weapon attack')
    end

    it 'is the table Kesser\'s Gambit points at' do
      expect(Abilities.roll_table_for("Kesser's Gambit")).to eq('Kesser Reversal Table')
    end

    it 'returns nil for an unknown table' do
      expect(Abilities.roll_table('No Such Table')).to be_nil
    end
  end

  describe 'validation' do
    def catalog(catalog_entries, roll_tables)
      Abilities::Catalog.new(config: Abilities::Config.load,
                             catalog: catalog_entries, roll_tables: roll_tables)
    end

    it 'rejects a table missing a face within 1..die' do
      c = catalog({}, { 'T' => { 'die' => 2,
                                 'entries' => { 1 => { 'name' => 'a', 'effect' => 'x' } } } })
      expect { c.validate! }.to raise_error(ArgumentError, /missing the entry for face 2/)
    end

    it 'rejects an entry missing its effect text' do
      c = catalog({}, { 'T' => { 'die' => 1, 'entries' => { 1 => { 'name' => 'a' } } } })
      expect { c.validate! }.to raise_error(ArgumentError, /face 1 is missing effect/)
    end

    it 'rejects an Ability pointing at an unknown roll_table' do
      c = catalog({ 'A' => { 'type' => 'talent', 'roll_table' => 'Ghost Table' } }, {})
      expect { c.validate! }.to raise_error(ArgumentError, /unknown roll_table "Ghost Table"/)
    end
  end
end
