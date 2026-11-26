require 'spec_helper'
require 'proficiencies'

# Proficiencies::Compute.breakdown — every step behind roll_inputs
# (proficiencies_design.md → "Break down the Roll inputs for a Proficiency").
RSpec.describe 'Proficiencies::Compute.breakdown', type: :model do
  BreakdownMock = Struct.new(:ranks_map, :attrs, :abilities_map, :ability_levels) do
    def ranks_for(key);          ranks_map.fetch(key, 0); end
    def attribute_value(attr);   attrs.fetch(attr.to_sym, 0); end
    def has_ability(name);       abilities_map[name] == true; end
    def level_for_ability(name); ability_levels.fetch(name, 0); end
  end

  def mock(ranks: {}, attrs: {}, abilities: {}, levels: {})
    BreakdownMock.new(ranks, attrs, abilities, levels)
  end

  def breakdown(key, creature, **opts)
    Proficiencies::Compute.breakdown(key: key, creature: creature, **opts)
  end

  it 'carries the ranks, the attribute and the Prowess they make' do
    b = breakdown('athletics', mock(ranks: { 'athletics' => 6 }, attrs: { str: 17 }))
    expect(b).to include(key: 'athletics', source_key: 'athletics', attribute: :str, attribute_value: 17,
                         attribute_contribution: 8, base_ranks: 6, floor_ranks: 0, ranks: 6,
                         prowess: 14, trained: true, penalty: 0)
    dice, bonus = DiceResolution.translate_prowess(14)
    expect(b).to include(dice_cap: dice, bonus: bonus)
  end

  it 'keeps the Non-Proficiency Penalty apart from the bonus' do
    b = breakdown('stealth', mock(attrs: { dex: 12 }))
    expect(b).to include(ranks: 0, trained: false, penalty: Proficiencies::Config.non_proficiency_penalty)
    expect(b[:bonus]).to eq(DiceResolution.translate_prowess(6)[1])
  end

  it 'never gives a Saving Throw the penalty' do
    b = breakdown('dex_save', mock(attrs: { dex: 12 }), attribute_override: :dex)
    expect(b).to include(ranks: 0, penalty: 0)
  end

  it 'shows the Floor Ability lifting the ranks' do
    floor = Proficiencies::Config.floor_ability
    b = breakdown('stealth', mock(attrs: { dex: 12 }, abilities: { floor => true }, levels: { floor => 4 }))
    expect(b).to include(base_ranks: 0, floor_ranks: 2, ranks: 2, trained: true, penalty: 0)
  end

  it "names the Substitution Ability's source when its Prowess wins" do
    sub = Proficiencies::Config.substitution_ability
    creature = mock(ranks: { 'perform_sing' => 6 }, attrs: { cha: 18 }, abilities: { sub => true })
    b = breakdown('deception', creature)
    expect(b).to include(key: 'deception', source_key: 'perform_sing', ranks: 6, prowess: 15)
  end

  it 'is what roll_inputs is built from' do
    floor = Proficiencies::Config.floor_ability
    sub   = Proficiencies::Config.substitution_ability
    creatures = [
      mock(ranks: { 'athletics' => 5 }, attrs: { str: 15, dex: 9 }),
      mock(attrs: { str: 3, dex: 21 }),
      mock(attrs: { str: 11, dex: 11 }, abilities: { floor => true }, levels: { floor => 6 }),
      mock(ranks: { 'perform_dance' => 7 }, attrs: { str: 8, dex: 10, cha: 16 }, abilities: { sub => true })
    ]
    creatures.each do |creature|
      %w[athletics acrobatics stealth].each do |key|
        b  = breakdown(key, creature)
        ri = Proficiencies::Compute.roll_inputs(key: key, creature: creature)
        total = b[:bonus] + b[:penalty]
        expect(ri[:dice_cap]).to eq(b[:dice_cap])
        expect(ri[:competency_modifier]).to eq(total.zero? ? nil : ['Competency', total])
      end
    end
  end
end
