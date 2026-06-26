require_relative 'support'

# Load-time validation, with emphasis on the new `polarity` rules.
RSpec.describe 'Abilities::Catalog#validate!' do
  def expect_invalid(entries, message)
    expect { build_ability_catalog(entries).validate! }
      .to raise_error(ArgumentError, /#{Regexp.escape(message)}/)
  end

  describe 'polarity' do
    it 'accepts positive and forced on a Spell' do
      expect(build_ability_catalog('A' => { 'type' => 'spell', 'polarity' => 'positive' },
                           'B' => { 'type' => 'spell', 'polarity' => 'forced' }).validate!).to be true
    end

    it 'rejects an unknown polarity value' do
      expect_invalid({ 'Bad' => { 'type' => 'spell', 'polarity' => 'sideways' } },
                     'unknown polarity')
    end

    it 'rejects polarity on a Talent' do
      expect_invalid({ 'Bad' => { 'type' => 'talent', 'polarity' => 'positive' } },
                     'polarity is not allowed on a Talent')
    end

    it 'allows an omitted polarity' do
      expect(build_ability_catalog('A' => { 'type' => 'spell' }).validate!).to be true
    end
  end

  describe 'core rules still hold' do
    it 'rejects an unknown type' do
      expect_invalid({ 'X' => { 'type' => 'gizmo' } }, 'unknown type')
    end

    it 'requires a threshold for physical damage_type' do
      expect_invalid({ 'X' => { 'type' => 'spell', 'damage_type' => 'physical' } },
                     'requires a threshold')
    end

    it 'rejects both a tier list and aspects' do
      expect_invalid({ 'X' => { 'type' => 'spell', 'tier' => [0, 1], 'aspects' => %w[a b] } },
                     'mutually exclusive')
    end
  end

  describe 'range' do
    it 'accepts an inline per-rank range formula' do
      expect(build_ability_catalog('A' => { 'type' => 'spell', 'range' => '50*rank' }).validate!).to be true
    end

    it 'rejects a string that is neither a known range nor an evaluable formula' do
      expect_invalid({ 'Bad' => { 'type' => 'spell', 'range' => 'Closee' } }, 'unknown range')
    end
  end

  it 'loads the shipped catalog without error' do
    expect { Abilities::Catalog.load }.not_to raise_error
  end
end
