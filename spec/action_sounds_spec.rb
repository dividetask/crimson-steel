require 'spec_helper'
require_relative '../lib/action_sounds'

# Sounds tied to actions (config/action_sounds.yml, docs/project/action_sounds.md).
RSpec.describe ActionSounds do
  it 'finds a sound by the action name, ignoring case and punctuation' do
    expect(described_class.path_for('Rage')).to eq('/sounds/RAGE_AGAIN.mp3')
    expect(described_class.path_for('fire ball')).to eq('/sounds/Fireball.mp3')
  end

  it 'plays a Spell’s sound for an item that holds it' do
    expect(described_class.path_for('Scroll of Fireball')).to eq('/sounds/Fireball.mp3')
    expect(described_class.path_for('Potion of Fireball')).to eq('/sounds/Fireball.mp3')
  end

  it 'has no sound for anything else' do
    expect(described_class.path_for('Heal')).to be_nil
  end
end
