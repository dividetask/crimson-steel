require 'spec_helper'
require 'encounter'
require 'abilities'

# Bardic Inspiration is a check-based channel: its Reservoir fills from the
# Successes of a Performance Check, so the rolled dice are a real skill Check
# and must obey the Performance skill's Dice Cap (not run up to Combat Pool
# Remaining). When several Performance skills are trained the builder offers a
# picker; this covers the pure detection that feeds it.
RSpec.describe 'Encounter::Special — channel Check skills' do
  # A Creature exposing both the proficiency interface (ranks/attributes, as in
  # spec/proficiencies/compute_spec.rb) and the `record` classes/skills the
  # detection reads.
  def creature(skills:, ranks: {}, attrs: {})
    Struct.new(:rec, :ranks_map, :attrs_map) do
      def record = rec
      def ranks_for(k) = ranks_map.fetch(k.to_s, 0)
      def attribute_value(a) = attrs_map.fetch(a.to_sym, 0)
      def has_ability(_n) = false
      def level_for_ability(_n) = 0
    end.new({ classes: { 'bard' => { level: 1, skills: skills } } }, ranks, attrs)
  end

  let(:bardic) { Abilities.catalog.ability('Bardic Inspiration') }

  describe '.check_channel?' do
    it 'is true for Bardic Inspiration (fills from check successes)' do
      expect(Encounter::Special.check_channel?(bardic)).to be(true)
    end

    it 'is false for a channel_dice / fire channel and for nil' do
      expect(Encounter::Special.check_channel?({ 'reservoir' => { 'fill' => { 'source' => 'channel_dice' } } })).to be(false)
      expect(Encounter::Special.check_channel?(nil)).to be(false)
    end
  end

  describe '.check_skills' do
    it "finds the bard's trained Performance skill with its Dice Cap + Competency" do
      acc = creature(skills: %w[perform_dance persuasion], ranks: { 'perform_dance' => 4 }, attrs: { cha: 6 })
      # perform_dance @ ranks 4, cha 6 → Dice Cap 8 (see compute_spec) — well
      # under the Combat-Pool-Remaining 11 the bug let through.
      expect(Encounter::Special.check_skills(acc, bardic)).to eq(
        [{ key: 'perform_dance', label: 'Perform (Dance)', dice_cap: 8, competency: ['Competency', 1] }]
      )
    end

    it 'lists every trained Performance skill when several qualify (the picker source)' do
      acc = creature(skills: %w[perform_sing perform_percussion],
                     ranks: { 'perform_sing' => 4, 'perform_percussion' => 2 }, attrs: { cha: 6 })
      out = Encounter::Special.check_skills(acc, bardic)
      expect(out.map { |s| s[:key] }).to eq(%w[perform_sing perform_percussion])
      expect(out.map { |s| s[:label] }).to eq(['Perform (Sing)', 'Perform (Percussion)'])
      out.each { |s| expect(s[:dice_cap]).to be_between(1, 10) } # always capped under 11
    end

    it 'returns nothing when the bard trains no Performance skill' do
      acc = creature(skills: %w[persuasion perception], attrs: { cha: 6 })
      expect(Encounter::Special.check_skills(acc, bardic)).to eq([])
    end
  end
end
