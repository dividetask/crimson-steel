require 'spec_helper'
require 'proficiencies'

RSpec.describe 'Proficiencies.look_up (Prefix Match)', type: :model do
  it 'exact match wins' do
    expect(Proficiencies.look_up('athletics')['attribute']).to eq('str')
  end

  it 'Set Instance resolves to the family entry' do
    expect(Proficiencies.look_up('perform_dance')['attribute']).to eq('cha')
  end

  it 'unknown key returns nil' do
    expect(Proficiencies.look_up('homebrew_skill')).to be_nil
  end

  it 'attribute_for returns the driving attribute symbol' do
    expect(Proficiencies.attribute_for('martial')).to eq(:dex)
    expect(Proficiencies.attribute_for('craft_alchemy')).to eq(:int)
  end
end
