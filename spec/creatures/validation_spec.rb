require 'spec_helper'
require 'creatures'

RSpec.describe 'Creatures::Record validation', type: :model do
  ATTRS = { 'str' => 10, 'dex' => 10, 'con' => 10, 'int' => 10, 'wis' => 10, 'cha' => 10 }.freeze

  it 'rejects a record missing `id`' do
    expect {
      Creatures::Record.normalize({ 'name' => 'X', 'race' => 'human', 'attributes' => ATTRS })
    }.to raise_error(ArgumentError, /missing/)
  end

  it 'rejects a record missing an attribute key' do
    expect {
      Creatures::Record.normalize({ 'id' => 1, 'name' => 'X', 'race' => 'human',
                                     'attributes' => { 'str' => 10 } })
    }.to raise_error(ArgumentError, /attributes/)
  end

  it 'rejects unknown race' do
    expect {
      Creatures::Record.normalize({ 'id' => 1, 'name' => 'X', 'race' => 'merfolk',
                                     'attributes' => ATTRS })
    }.to raise_error(ArgumentError, /unknown race/)
  end

  it 'rejects bare Set Skill keys in trained-skill lists' do
    expect {
      Creatures::Record.normalize({
        'id' => 1, 'name' => 'X', 'race' => 'human', 'attributes' => ATTRS,
        'advancement' => { 'classes' => { 'cleric' => { 'level' => 1, 'skills' => ['perform_'] } } }
      })
    }.to raise_error(ArgumentError, /bare Set Skill/)
  end

  it 'rejects unknown class keys' do
    expect {
      Creatures::Record.normalize({
        'id' => 1, 'name' => 'X', 'race' => 'human', 'attributes' => ATTRS,
        'advancement' => { 'classes' => { 'homebrew_class' => 1 } }
      })
    }.to raise_error(ArgumentError, /unknown class/)
  end

  it 'rejects Archetype Exclusivity violations: parent + archetype' do
    expect {
      Creatures::Record.normalize({
        'id' => 1, 'name' => 'X', 'race' => 'human', 'attributes' => ATTRS,
        'advancement' => { 'classes' => { 'rogue' => 3, 'arcane_trickster' => 1 } }
      })
    }.to raise_error(ArgumentError, /Archetype Exclusivity/)
  end

  it 'accepts multi-classing across unrelated Classes' do
    rec = Creatures::Record.normalize({
      'id' => 1, 'name' => 'X', 'race' => 'human', 'attributes' => ATTRS,
      'advancement' => { 'classes' => { 'rogue' => 3, 'fighter' => 2 } }
    })
    expect(rec[:classes].keys).to contain_exactly('rogue', 'fighter')
  end

  it 'accepts the integer-shorthand class entry form' do
    rec = Creatures::Record.normalize({
      'id' => 1, 'name' => 'X', 'race' => 'human', 'attributes' => ATTRS,
      'advancement' => { 'classes' => { 'fighter' => 3 } }
    })
    expect(rec[:classes]['fighter']).to include(level: 3, skills: [], choices: {})
  end

  it 'rejects unknown attribute keys in tier_attribute_advancement' do
    expect {
      Creatures::Record.normalize({
        'id' => 1, 'name' => 'X', 'race' => 'human', 'attributes' => ATTRS,
        'advancement' => { 'tier_attribute_advancement' => ['str', 'magic'] }
      })
    }.to raise_error(ArgumentError, /magic/)
  end
end
