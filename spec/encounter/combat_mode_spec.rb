require 'spec_helper'
require 'encounter'
require 'conditions'
require 'tmpdir'

RSpec.describe 'Encounter combat-mode operations' do
  describe Encounter::CombatPool do
    it 'computes the Budget' do
      # martial 4, attribute 12, tier 0 (Turns Per Round[0] = 1):
      # floor(((4 * 2) + 12) / 1) = 20
      expect(described_class.budget(martial_ranks: 4, attribute: 12, tier: 0)).to eq(20)
    end

    it 'buys the largest pool whose tiered cost fits the Budget' do
      # Per the design's closed form, cost(11)=10 <= 10 < cost(12)=12.
      expect(described_class.buy(10)).to eq(11)
    end

    it 'guarantees at least Combat Pool Step points' do
      expect(described_class.buy(0)).to eq(Encounter::Config.combat_pool_step)
    end
  end

  describe Encounter::TimeTicks do
    it 'sets Time Ticks Per Round to the highest tier' do
      expect(described_class.ticks_per_round([1, 3, 4])).to eq(4)
    end

    it 'computes the floored-midpoint schedule' do
      expect(described_class.schedule(1, 4)).to eq([2])
      expect(described_class.schedule(3, 4)).to eq([1, 3])
      expect(described_class.schedule(4, 4)).to eq([1, 2, 3, 4])
    end
  end

  describe Encounter::Initiative do
    it 'encodes rolled dice as a descending Dice Result String' do
      expect(described_class.resolve([8, 6, 5, 3])).to eq('8653')
    end

    it 'encodes a 10 as the configured Critical label' do
      expect(described_class.resolve([10, 9, 7])).to eq('X97')
    end

    it 'positive Luck rerolls the lowest non-Critical dice' do
      queue = [7, 9]
      roller = ->(_n) { [queue.shift] }
      # [10,6,5,2] luck 2: reroll the 5 and 2 (lowest non-crit), 10 skipped.
      result = described_class.resolve([10, 6, 5, 2], luck: 2, roller: roller)
      expect(result).to eq('X976') # {10,6,9,7} sorted desc
    end

    it 'negative Luck rerolls the highest non-Failure dice' do
      queue = [4, 3]
      roller = ->(_n) { [queue.shift] }
      result = described_class.resolve([9, 8, 1], luck: -2, roller: roller)
      expect(result).to eq('431') # {4,3,1}
    end

    it 'positive Insight prefers the lowest crit-capable die' do
      expect(described_class.resolve([6, 4], insight: 4)).to eq('X4') # 6 -> 10
    end

    it 'positive Insight falls back to the highest non-Critical die' do
      expect(described_class.resolve([10, 5, 3], insight: 1)).to eq('X63') # 5 -> 6
    end

    it 'negative Insight lowers the highest die, clamped at 1' do
      expect(described_class.resolve([7, 4], insight: -3)).to eq('44')
      expect(described_class.resolve([7, 4], insight: -8)).to eq('41')
    end
  end

  describe Encounter::Severity do
    it 'uses the catalog severity for non-physical damage (+damage_per_hit)' do
      out = described_class.compute(raw: 5, type: 'fire')
      expect(out[:severity_map]).to eq(moderate: 6)
    end

    it 'inherits runtime bucketing from the physical parent' do
      out = described_class.compute(raw: 7, type: 'slashing', threshold: 2, damage_resilience: 1)
      expect(out[:severity_map]).to eq(minor: 3, moderate: 3, major: 1)
    end

    it 'routes acid to the Acid Counter' do
      out = described_class.compute(raw: 6, type: 'acid')
      expect(out[:severity_map]).to eq(moderate: 6)
      expect(out[:side_effects]).to include(hash_including(kind: 'acid', amount: 6))
    end

    it 'inflicts Shock for cold' do
      out = described_class.compute(raw: 4, type: 'cold')
      expect(out[:severity_map]).to eq(minor: 4)
      expect(out[:side_effects]).to include(hash_including(kind: 'inflict', effect: 'shock', amount: 4))
    end

    it 'upgrades radiant severity against undead' do
      expect(described_class.compute(raw: 5, type: 'radiant', target_tags: ['undead'])[:severity_map]).to eq(major: 5)
      expect(described_class.compute(raw: 5, type: 'radiant')[:severity_map]).to eq(moderate: 5)
    end
  end

  describe 'Unaware (inferred from Round + initiative order)' do
    let(:tmpdir) { Dir.mktmpdir('enc-unaware') }
    after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

    def creature
      Struct.new(:tier, :tags, :max_hit_points, :max_mana).new(0, [], 30, 8)
    end

    def state
      Encounter::State.new({}, data_path: File.join(tmpdir, 'e.json'),
                           creature_lookup: ->(_id) { creature },
                           conditions_for: ->(_id) { Conditions::Instance.new })
    end

    it 'is true in Round 1 for Combatants below the Acting Combatant in initiative' do
      s = state
      a = s.add_combatant('1'); b = s.add_combatant('2'); c = s.add_combatant('3')
      s.start_combat
      s.set_initiative(a[:id], '9'); s.set_initiative(b[:id], '7'); s.set_initiative(c[:id], '5')
      s.set_acting_combatant(a[:id]) # top of initiative acts first

      expect(s.round_number).to eq(1)
      expect(s.unaware?(a[:id])).to be false # acting — at the front, has acted
      expect(s.unaware?(b[:id])).to be true  # below in initiative, not yet acted
      expect(s.unaware?(c[:id])).to be true

      s.set_acting_combatant(b[:id]) # turn passes to the second
      expect(s.unaware?(a[:id])).to be false # already acted
      expect(s.unaware?(b[:id])).to be false # acting now
      expect(s.unaware?(c[:id])).to be true  # still below, hasn't acted
    end

    it 'is false for everyone before Initiative is seated (no Acting Combatant)' do
      # No one can have acted yet, but Combat is not the "Round 1 unaware"
      # window until the order is seated; with no Acting Combatant we treat
      # everyone as Unaware (nothing has acted).
      s = state
      a = s.add_combatant('1'); b = s.add_combatant('2')
      s.start_combat
      expect(s.unaware?(a[:id])).to be true
      expect(s.unaware?(b[:id])).to be true
    end

    it 'is false for everyone from Round 2 on' do
      s = state
      a = s.add_combatant('1'); b = s.add_combatant('2')
      s.start_combat
      s.set_initiative(a[:id], '9'); s.set_initiative(b[:id], '7')
      s.set_acting_combatant(a[:id])
      s.advance_turn # tpr 1 → wraps the tick and bumps the Round
      expect(s.round_number).to be >= 2
      expect(s.unaware?(a[:id])).to be false
      expect(s.unaware?(b[:id])).to be false
    end
  end

  describe 'Turn order with un-rolled Combatants' do
    let(:tmpdir) { Dir.mktmpdir('enc-order') }
    after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

    # A Creature double that can actually act (non-zero attributes, so the
    # death check doesn't trip), so advance_turn moves rather than skipping.
    def creature
      obj = Object.new
      obj.define_singleton_method(:tier) { 0 }
      obj.define_singleton_method(:tags) { [] }
      obj.define_singleton_method(:max_hit_points) { 30 }
      obj.define_singleton_method(:max_mana) { 8 }
      obj.define_singleton_method(:attribute_value) { |_a| 10 }
      obj.define_singleton_method(:ranks_for) { |_k| 4 }
      obj.define_singleton_method(:name) { 'Mob' }
      obj
    end

    def state
      Encounter::State.new({}, data_path: File.join(tmpdir, 'e.json'),
                           creature_lookup: ->(_id) { creature },
                           conditions_for: ->(_id) { Conditions::Instance.new })
    end

    # Combatants who have not rolled Initiative (empty string) sort LAST in
    # the turn order, matching the Combat Tracker's display. Regression: they
    # used to sort first, so ending the bottom row's turn jumped mid-list
    # instead of rolling the Round over.
    it 'sorts un-rolled Combatants last and rolls the Round from the bottom row' do
      s = state
      rolled = s.add_combatant('1'); unrolled = s.add_combatant('2')
      s.start_combat
      s.set_initiative(rolled[:id], '9') # unrolled keeps empty Initiative

      expect(s.acting_combatants.map { |c| c[:id] }).to eq([rolled[:id], unrolled[:id]])

      s.set_acting_combatant(rolled[:id])
      s.advance_turn
      expect(s.acting_combatant_id).to eq(unrolled[:id]) # next, same Round
      expect(s.round_number).to eq(1)

      s.advance_turn # ending the last (bottom) row rolls the Round over
      expect(s.acting_combatant_id).to eq(rolled[:id])
      expect(s.round_number).to eq(2)
    end
  end

  describe '#apply_move' do
    let(:tmpdir) { Dir.mktmpdir('enc-move') }
    after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

    def creature
      obj = Object.new
      obj.define_singleton_method(:tier) { 1 }
      obj.define_singleton_method(:tags) { [] }
      obj.define_singleton_method(:max_hit_points) { 30 }
      obj.define_singleton_method(:max_mana) { 8 }
      obj.define_singleton_method(:attribute_value) { |_a| 16 }
      obj.define_singleton_method(:ranks_for) { |_k| 4 }
      obj
    end

    def state
      Encounter::State.new({}, data_path: File.join(tmpdir, 'e.json'),
                           creature_lookup: ->(_id) { creature },
                           conditions_for: ->(_id) { Conditions::Instance.new })
    end

    it 'spends the Move Cost in Combat Pool dice' do
      s = state
      c = s.add_combatant('1')
      before = s.combat_pool_remaining(c[:id])
      out = s.apply_move(c[:id])
      expect(out[:ok]).to be true
      expect(out[:pool_spent]).to eq(Encounter::Config.move_cost)
      expect(s.combat_pool_remaining(c[:id])).to eq(before - Encounter::Config.move_cost)
    end

    it 'refuses when the Combat Pool cannot afford the cost, spending nothing' do
      s = state
      c = s.add_combatant('1')
      leave = Encounter::Config.move_cost - 1
      pool  = s.combat_pool_remaining(c[:id])
      s.spend_combat_pool(c[:id], pool - leave) # drain to just below the cost
      out = s.apply_move(c[:id])
      expect(out[:ok]).to be false
      expect(out[:error]).to match(/Combat Pool/)
      expect(s.combat_pool_remaining(c[:id])).to eq(leave)
    end
  end
end
