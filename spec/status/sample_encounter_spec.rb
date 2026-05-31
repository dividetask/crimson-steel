require 'status/sample_encounter'

RSpec.describe Status::SampleEncounter do
  # Badge kinds the Combat Tracker has CSS for (.cond-<kind> in
  # public/style.css). Sample badges must stay within this set so they
  # render with a real color rather than falling through unstyled.
  KNOWN_BADGE_KINDS = %w[shock pain bleed poison disease curse major other].freeze

  describe '.scenarios' do
    subject(:scenarios) { described_class.scenarios }

    it 'returns a labelled scenario for each display axis' do
      expect(scenarios).to be_an(Array)
      expect(scenarios).not_to be_empty
      scenarios.each do |sc|
        expect(sc[:label]).to be_a(String).and(satisfy { |l| !l.empty? })
        expect(sc).to include(:viewer, :combat_active, :round_label, :rows)
        expect(%i[dm player]).to include(sc[:viewer])
        expect([true, false]).to include(sc[:combat_active])
        expect(sc[:rows]).to be_an(Array)
      end
    end

    it 'exercises both viewer roles and both Combat states' do
      expect(scenarios.map { |s| s[:viewer] }.uniq).to contain_exactly(:dm, :player)
      expect(scenarios.map { |s| s[:combat_active] }.uniq).to contain_exactly(true, false)
    end

    it 'includes an empty-roster scenario (the "no combatants" message)' do
      expect(scenarios).to include(a_hash_including(rows: []))
    end
  end

  describe '.roster' do
    subject(:rows) { described_class.roster }

    it 'shapes every row the way the Initiative Stub consumes it' do
      rows.each do |row|
        expect(row.keys).to include(
          :combatant_id, :creature_id, :name, :initiative,
          :acting, :can_act, :hp, :mana, :toxicity, :combat_pool, :badges
        )
        expect(row[:name]).to be_a(String).and(satisfy { |n| !n.empty? })
        expect([true, false]).to include(row[:acting], row[:can_act])
        expect(row[:badges]).to be_an(Array)
      end
    end

    it 'has unique Combatant ids' do
      ids = rows.map { |r| r[:combatant_id] }
      expect(ids).to eq(ids.uniq)
    end

    it 'covers the acting highlight, a cannot-act row, and a fresh (un-rolled) row' do
      expect(rows.count { |r| r[:acting] }).to eq(1)
      expect(rows).to include(a_hash_including(can_act: false))
      # A freshly spawned Combatant: Initiative not rolled and vitals
      # not wired, so the numeric columns render as dashes.
      fresh = rows.find { |r| r[:initiative].nil? }
      expect(fresh).not_to be_nil
      expect(fresh.values_at(:hp, :mana, :toxicity, :combat_pool)).to all(be_nil)
    end

    it 'uses only badge kinds the tracker has styling for' do
      kinds = rows.flat_map { |r| r[:badges] }.map { |b| b[:kind] }
      expect(kinds).not_to be_empty
      expect(kinds.uniq).to all(satisfy { |k| KNOWN_BADGE_KINDS.include?(k) })
      rows.flat_map { |r| r[:badges] }.each do |b|
        expect(b[:label]).to be_a(String).and(satisfy { |l| !l.empty? })
      end
    end

    it 'partitions each HP value so current + damage segments equal max' do
      rows.map { |r| r[:hp] }.compact.each do |hp|
        # current may be negative (overkilled past 0); the segments still
        # sum back to Max.
        expect(hp[:current] + hp[:minor] + hp[:moderate] + hp[:major]).to eq(hp[:max])
      end
    end

    it 'includes an overkilled Combatant with negative current HP' do
      negs = rows.map { |r| r[:hp] }.compact.select { |hp| hp[:current].negative? }
      expect(negs).not_to be_empty
    end
  end
end
