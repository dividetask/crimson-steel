require 'spec_helper'
require 'creatures'
require 'creatures/advancement'
require 'tmpdir'

# Promote a generated/spawned monster into a named NPC: rename + group -> npc,
# persisted to its source file so it survives a reload (and post-combat cleanup
# treats it as an ally rather than deleting it).
RSpec.describe 'Creatures.promote_to_npc' do
  around(:each) do |ex|
    Dir.mktmpdir('promote-npc') do |dir|
      Creatures::Dataset.data_dir = dir
      ex.run
    ensure
      Creatures::Dataset.reset!
    end
  end
  before(:each) { Creatures::Dataset.load! }

  it 'renames a spawned monster and sets its group to npc' do
    id = Creatures.spawn_from_template(306) # Common Goblin (enemy template)
    expect(Creatures.lookup(id).group).to eq('enemy')

    Creatures.promote_to_npc(id, 'Grix the Turncoat')
    acc = Creatures.lookup(id)
    expect(acc.name).to eq('Grix the Turncoat')
    expect(acc.group).to eq('npc')
  end

  it 'keeps the current name when none is supplied (blank or nil)' do
    id = Creatures.spawn_from_template(306)
    before = Creatures.lookup(id).name
    Creatures.promote_to_npc(id, '   ')
    acc = Creatures.lookup(id)
    expect(acc.name).to eq(before)
    expect(acc.group).to eq('npc')
  end

  it 'raises for an unknown Creature id' do
    expect { Creatures.promote_to_npc(10_999_999, 'X') }
      .to raise_error(ArgumentError, /no Creature/)
  end

  it 'drops the enemy_template tag so the sheet renders as a character, not a template' do
    # Promote a template directly (not a spawned instance): it must shed the
    # enemy_template tag, otherwise its sheet shows the template (spawn) view.
    Creatures.promote_to_npc(306, 'Grix the Turncoat')
    acc = Creatures.lookup(306)
    expect(acc.group).to eq('npc')
    expect(Array(acc.tags)).not_to include('enemy_template')
  end
end
