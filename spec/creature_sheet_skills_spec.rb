require 'spec_helper'
require 'creature_sheet'
require 'proficiencies'
require 'dice_resolution'
require_relative 'creatures/fixtures'

# The Character Sheet's Skills heading opens a modal listing every Skill
# (trained and untrained) with the Creature's Dice Cap + Bonus and a Roll
# button. CreatureSheet.all_skills feeds that list; CreatureSheet.skill_roll
# builds the Roll Resolution Stub hash for one Skill's Roll button.
RSpec.describe 'CreatureSheet skill list + roll' do
  include CreaturesFixtures

  let(:accessor) do
    # A fighter trained in athletics, plus a trained Set-Skill instance.
    Creatures::Accessor.new(
      record(classes: { 'fighter' => { level: 4, skills: %w[athletics craft_blacksmith] } })
    )
  end

  describe '.all_skills' do
    subject(:skills) { CreatureSheet.all_skills(accessor) }

    it 'lists both trained and untrained Skills' do
      names = skills.map { |s| s[:key] }
      expect(names).to include('athletics')      # trained
      expect(names).to include('stealth')        # untrained concrete Skill
      expect(names).to include('craft_blacksmith') # trained Set-Skill instance
    end

    it 'excludes bare Set-Skill families (keys ending in "_")' do
      expect(skills.map { |s| s[:key] }).not_to include(a_string_ending_with('_'))
    end

    it 'flags trained vs untrained and carries dice + bonus' do
      athletics = skills.find { |s| s[:key] == 'athletics' }
      stealth   = skills.find { |s| s[:key] == 'stealth' }
      expect(athletics[:trained]).to be true
      expect(athletics[:ranks]).to be > 0
      expect(stealth[:trained]).to be false
      # Every row carries an integer Dice Cap and Bonus for display.
      expect(athletics[:dice]).to be_a(Integer)
      expect(athletics[:bonus]).to be_a(Integer)
    end

    it 'is sorted by display name' do
      names = skills.map { |s| s[:name] }
      expect(names).to eq(names.sort)
    end
  end

  describe '.skill_roll' do
    it 'builds a Roll Resolution Stub hash that passes validation' do
      roll = CreatureSheet.skill_roll(accessor, 'athletics')
      expect(roll).to include(:creature_name, :roll_name, :dice_count, :tn, :die_size)
      expect(roll[:roll_name]).to eq('Athletics check')
      expect { DiceResolution::Roll.validate!(roll) }.not_to raise_error
    end

    it 'folds the Skill Bonus into the Target Number via Dice Resolution' do
      roll = CreatureSheet.skill_roll(accessor, 'athletics')
      expected = DiceResolution.compute_target_number(roll[:bonus_penalty_list])
      expect(roll[:tn]).to eq(expected[:tn])
      expect(roll[:starting_value]).to eq(expected[:starting_value])
    end

    it 'returns nil for a bare Set-Skill family or unknown key' do
      expect(CreatureSheet.skill_roll(accessor, 'craft_')).to be_nil
      expect(CreatureSheet.skill_roll(accessor, '')).to be_nil
    end
  end
end
