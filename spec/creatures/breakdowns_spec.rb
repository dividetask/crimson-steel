require 'spec_helper'
require_relative 'fixtures'

# The parts behind Max HP, Max Mana and ranks, for showing the math
# (creatures_design.md → Creature Accessor). Each breakdown is what its total
# is computed from, so the two cannot disagree.
RSpec.describe 'Creatures breakdowns', type: :model do
  include CreaturesFixtures

  describe 'hit_points_breakdown' do
    it "carries the Tier's HP Formula, the values it read, and the total" do
      a = Creatures::Accessor.new(korth)
      b = a.hit_points_breakdown
      expect(b[:tier]).to eq(2)
      expect(b[:formula]).to eq(Creatures::Advancement.data['HP Formula'][2])
      expect(b[:vars][:con]).to eq(a.attribute_value(:con))
      expect(b[:base]).to eq(2 * a.attribute_value(:con))
      expect(b[:total]).to eq(b[:base] + b[:modifiers])
      expect(a.max_hit_points).to eq(b[:total])
    end
  end

  describe 'mana_breakdown' do
    it 'splits Max Mana into the Tier formula and each Class' do
      a = Creatures::Accessor.new(record(
        tier: 2, attributes: { str: 10, dex: 10, con: 10, int: 14, wis: 10, cha: 10 },
        classes: { wizard: { level: 3 }, fighter: { level: 2 } }
      ))
      b = a.mana_breakdown
      expect(b[:formula]).to eq(Creatures::Advancement.data['Mana Base Formula'][2])
      expect(b[:base]).to eq(a.attribute_value(:int))
      expect(b[:classes].map { |c| c[:class_key] }).to eq(%w[wizard fighter])
      b[:classes].each { |c| expect(c[:amount]).to eq(c[:per_level] * c[:level]) }
      expect(b[:total]).to eq(b[:base] + b[:classes].sum { |c| c[:amount] } + b[:modifiers])
      expect(a.max_mana).to eq(b[:total])
    end
  end

  describe 'rank_sources' do
    let(:multi) do
      Creatures::Accessor.new(record(
        classes: { fighter: { level: 4, skills: %w[athletics] }, rogue: { level: 3, skills: %w[stealth athletics] } }
      ))
    end

    it 'gives one entry per Class, summing to ranks_for' do
      %w[athletics stealth arcana martial str_save dex_save].each do |key|
        sources = multi.rank_sources(key)
        expect(sources.map { |s| s[:class_key] }).to eq(%w[fighter rogue]), key
        expect(sources.sum { |s| s[:ranks] }).to eq(multi.ranks_for(key)), key
        sources.each do |s|
          expect(s[:ranks]).to eq(Proficiencies::Ranks.apply_rate(s[:level], s[:rate] || :_none)), key
        end
      end
    end

    it 'has no rate for a Skill the Class Entry has not trained, but still its category' do
      fighter, rogue = multi.rank_sources('stealth')
      expect(fighter).to include(rate: nil, ranks: 0)
      expect(fighter[:category]).to eq(Proficiencies::Ranks.skill_rate('fighter', 'stealth', trained: true))
      expect(rogue[:rate]).to eq(rogue[:category])
      expect(rogue[:ranks]).to be > 0
    end

    it 'always advances Saves and Martial' do
      a = Creatures::Accessor.new(korth)
      (%w[martial] + %w[str dex con int wis cha].map { |k| "#{k}_save" }).each do |key|
        a.rank_sources(key).each { |s| expect(s[:rate]).to eq(s[:category]).and(be_a(Symbol)), key }
      end
    end
  end
end
