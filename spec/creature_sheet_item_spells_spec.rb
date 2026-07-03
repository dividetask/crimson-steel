require 'spec_helper'
require 'creature_sheet'
require 'equipment'

# A Creature can cast Spells from an equipped spell-granting item (a Ring /
# Circlet with `grants_spell`), whose Spells are named on the catalog
# definition — a `spells` list (Ring of Shooting Stars) or a single `spell`.
# These must surface under Item Spells alongside scroll / wand `stored_spell`s.
RSpec.describe 'CreatureSheet.item_spells — granted-spell items' do
  # Minimal Stack stand-in: only the fields item_spells reads.
  Stack = Struct.new(:item_type, :equipped, :stored_spell, keyword_init: true)

  # Fake Equipment catalog returning a definition per item_type.
  def fake_catalog(defs)
    Class.new do
      define_method(:definition_of) { |item_type| defs[item_type] }
    end.new
  end

  let(:accessor) { Object.new }

  it 'lists every Spell named in an equipped item\'s `spells` list, at each Spell\'s own Tier' do
    stack = Stack.new(item_type: 'Ring of Shooting Stars', equipped: true, stored_spell: nil)
    allow(CreatureSheet).to receive(:inventory).and_return([stack])
    allow(Equipment).to receive(:catalog).and_return(
      fake_catalog('Ring of Shooting Stars' =>
        { 'grants_spell' => true, 'spells' => ['Spark Shower', 'Shooting Stars'] })
    )

    groups = CreatureSheet.item_spells(accessor)
    names_by_tier = groups.each_with_object({}) { |g, h| h[g[:tier]] = g[:names] }
    # Spark Shower is the Tier-0 name, Shooting Stars the Tier-1 name of the
    # same Tier-axis Spell — each lands at its own Tier, not the Ring's.
    expect(names_by_tier[0]).to include('Spark Shower')
    expect(names_by_tier[1]).to include('Shooting Stars')
  end

  it 'lists a single-`spell` granted item' do
    stack = Stack.new(item_type: 'Circlet of Entangle', equipped: true, stored_spell: nil)
    allow(CreatureSheet).to receive(:inventory).and_return([stack])
    allow(Equipment).to receive(:catalog).and_return(
      fake_catalog('Circlet of Entangle' => { 'grants_spell' => true, 'spell' => 'Entangle' })
    )
    names = CreatureSheet.item_spells(accessor).flat_map { |g| g[:names] }
    expect(names).to include('Entangle')
  end

  it 'ignores a granted-spell item that is not equipped' do
    stack = Stack.new(item_type: 'Ring of Shooting Stars', equipped: false, stored_spell: nil)
    allow(CreatureSheet).to receive(:inventory).and_return([stack])
    allow(Equipment).to receive(:catalog).and_return(
      fake_catalog('Ring of Shooting Stars' =>
        { 'grants_spell' => true, 'spells' => ['Spark Shower', 'Shooting Stars'] })
    )
    expect(CreatureSheet.item_spells(accessor)).to eq([])
  end

  it 'still lists a scroll / wand `stored_spell`' do
    stack = Stack.new(item_type: 'Scroll of Message', equipped: false, stored_spell: 'Message')
    allow(CreatureSheet).to receive(:inventory).and_return([stack])
    allow(Equipment).to receive(:catalog).and_return(fake_catalog({}))
    names = CreatureSheet.item_spells(accessor).flat_map { |g| g[:names] }
    expect(names).to include('Message')
  end
end
