require 'spec_helper'
require 'encounter'
require 'abilities'

# Non-player vitals are the DM's to see: players never see a non-PC
# combatant's Mana / Toxicity / Pool / Conditions on the Combat Tracker, and
# see only its HP bar (not the raw numbers) — except that a cleric with See
# Injury also sees its HP numbers and Magic Toxicity. Player Characters (the
# party's own) always render in full.
RSpec.describe Encounter::Visibility do
  # A fully-populated tracker row, as build_tracker_row would produce.
  def row(is_pc:, can_act: true)
    {
      combatant_id: 1, creature_id: 10, name: 'Goblin',
      initiative: '85', acting: false, can_act: can_act,
      hp:          { max: 20, minor: 0, moderate: 0, major: 0, current: 12 },
      mana:        { remaining: 3, max: 5 },
      toxicity:    { value: 2, threshold: 8 },
      combat_pool: { remaining: 4, max: 6 },
      badges:      [{ kind: 'shock', label: '2 Shock' }],
      is_pc:       is_pc
    }
  end

  describe '.redact_rows' do
    it 'leaves every column intact for the DM' do
      rows = [row(is_pc: false)]
      out = described_class.redact_rows(rows, viewer: :dm, sees_injury: false)
      expect(out).to eq(rows)
    end

    it 'hides a non-PC Mana / Toxicity / Conditions from a player without See Injury' do
      out = described_class.redact_rows([row(is_pc: false)], viewer: :player, sees_injury: false)
      r = out.first
      expect(r[:mana]).to be_nil
      expect(r[:toxicity]).to be_nil
      expect(r[:badges]).to eq([])
    end

    it 'keeps Combat Pool visible to players (not hidden)' do
      out = described_class.redact_rows([row(is_pc: false)], viewer: :player, sees_injury: false)
      expect(out.first[:combat_pool]).to eq(remaining: 4, max: 6)
    end

    it 'keeps a non-PC HP bar but withholds its raw numbers from a player without See Injury' do
      out = described_class.redact_rows([row(is_pc: false)], viewer: :player, sees_injury: false)
      hp = out.first[:hp]
      # The bar reads its segment widths from these, so they must survive...
      expect(hp[:current]).to eq(12)
      expect(hp[:max]).to eq(20)
      # ...but the row is flagged so the view withholds the current/max text.
      expect(hp[:hide_numbers]).to be(true)
    end

    it 'redacts NPCs the same as enemies (any non-PC combatant)' do
      # An NPC and an enemy both arrive as is_pc: false — both are redacted.
      out = described_class.redact_rows([row(is_pc: false)], viewer: :player, sees_injury: false)
      expect(out.first[:mana]).to be_nil
      expect(out.first[:hp][:hide_numbers]).to be(true)
    end

    it 'shows a non-PC HP and Toxicity — but not Mana or Conditions — to a See Injury cleric' do
      out = described_class.redact_rows([row(is_pc: false)], viewer: :player, sees_injury: true)
      r = out.first
      expect(r[:hp]).to eq(max: 20, minor: 0, moderate: 0, major: 0, current: 12)
      expect(r[:toxicity]).to eq(value: 2, threshold: 8)
      expect(r[:combat_pool]).to eq(remaining: 4, max: 6) # Combat Pool always visible
      expect(r[:mana]).to be_nil
      expect(r[:badges]).to eq([])
    end

    it "leaves the party's own Player Character rows untouched for players" do
      pc = row(is_pc: true)
      out = described_class.redact_rows([pc], viewer: :player, sees_injury: false)
      expect(out.first).to eq(pc)
    end

    it 'does not leak a non-PC incapacitation through the cannot-act highlight' do
      out = described_class.redact_rows([row(is_pc: false, can_act: false)], viewer: :player, sees_injury: false)
      expect(out.first[:can_act]).to be(true)
    end

    it 'copies redacted rows rather than mutating the originals' do
      original = row(is_pc: false)
      described_class.redact_rows([original], viewer: :player, sees_injury: false)
      expect(original[:hp]).not_to be_nil
      expect(original[:badges]).not_to be_empty
    end
  end
end

RSpec.describe 'See Injury ability description' do
  it 'is on file in the abilities catalog' do
    entry = Abilities.lookup_modifier_ability('see_injury')
    expect(entry).not_to be_nil
    expect(entry[:description]).to start_with('You can see injuries, afflictions, magical saturation')
    expect(entry[:description]).to include('This ability does not work if you are blinded.')
  end
end
