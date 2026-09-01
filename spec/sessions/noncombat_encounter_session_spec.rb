require_relative 'support/session_helpers'

# The scene after the fight: no Combat, no initiative — the party makes
# camp, someone searches the bodies, the wounded are treated, potions and
# scrolls come out of packs, and the clock moves.
#
# This is where the healing and warding Spells get their full sweep: the
# whole Heal axis and the whole Ward axis, cast by the party's high
# cleric, checked against the tables in spells.yaml.
RSpec.describe 'Non-combat session — camp on the caravan road', :session do
  # Heal's effect_hash, by Tier (spells.yaml → Heal).
  HEAL_TIERS = [
    ['Heal Petty Wounds',    0, { minor: 2,  moderate: 0,  major: 0 }],
    ['Heal Lesser Wounds',   1, { minor: 4,  moderate: 2,  major: 0 }],
    ['Heal Simple Wounds',   2, { minor: 8,  moderate: 4,  major: 0 }],
    ['Heal Moderate Wounds', 3, { minor: 16, moderate: 8,  major: 1 }],
    ['Heal Advanced Wounds', 4, { minor: 32, moderate: 16, major: 2 }],
    ['Heal Extreme Wounds',  5, { minor: 64, moderate: 32, major: 4 }]
  ].freeze

  # Ward's temp_hp, by Tier (spells.yaml → Ward).
  WARD_TIERS = [
    ['Trivial Ward',  3], ['Lesser Ward',   5], ['Standard Ward', 8],
    ['Improved Ward', 12], ['Advanced Ward', 16], ['Superior Ward', 20]
  ].freeze

  # The skirmish that fills the camp with work. A Tier-0 goblin cannot
  # scratch a Tier-2 Character — only the Tier-2 Bandit Captain leaves
  # wounds worth healing.
  before do
    session.exclude_from_combat('Ash Windmere')
    session.dm_get('/encounter')
    @captain = session.spawn_enemy('Bandit Captain', as: 'Bandit Captain')
    session.start_combat
    session.take_turn(@captain)
    session.attack(by: @captain, on: 'Garroth Vask', dice: [10, 10, 9, 9, 8, 8])
    session.end_combat
    session.transcript.scene('Camp — the fight is over')
  end

  it 'leaves Garroth wounded across every Severity, and bleeding' do
    expect(session.total_hp_damage('Garroth Vask')).to be > 0
    expect(session.hp_damage('Garroth Vask').keys).to include(:minor, :moderate, :major)
    expect(session.afflictions('Garroth Vask')).to have_key('bleeding')
  end

  describe 'a player rolls a Skill' do
    it 'records the dice in the DM Roll Log rather than trusting the player' do
      before_count = session.roll_log.length

      result = session.skill_roll(by: 'Ash Windmere', skill: 'perception',
                                  dice: [9, 8, 3, 7, 2, 6])

      expect(result[:dois]).to be_a(Integer)
      entries = session.roll_log
      expect(entries.length).to eq(before_count + 1)
      # The DM sees the actual dice, not just the total.
      expect(entries.first['dice']).to eq([9, 8, 3, 7, 2, 6])
      expect(entries.first['dois']).to eq(result[:dois])
      expect(entries.first['creature_name']).to eq('Ash Windmere')
    end
  end

  describe 'consumables' do
    it 'spends a Potion, applies Item-Form Toxicity, and heals no Mana cost' do
      before_potions = session.quantity_of('Potion of Heal', owner: 'Thora Stoneveil')
      before_mana    = session.mana_spent('Thora Stoneveil')

      result = session.cast('Heal', by: 'Thora Stoneveil', on: 'Garroth Vask',
                            item: true, dice: [9, 8, 7, 6, 5])

      expect(result['ok']).not_to be false
      expect(result['consumable']).to be true
      expect(result['item_consumed']).to eq('Potion of Heal Lesser Wounds')
      expect(session.quantity_of('Potion of Heal', owner: 'Thora Stoneveil'))
        .to eq(before_potions - 1)
      # A Potion costs no Mana but imposes Item-Form Toxicity.
      expect(session.mana_spent('Thora Stoneveil')).to eq(before_mana)
      expect(result.dig('toxicity', 'requested')).to be > 0
    end
  end

  describe 'the healing Spells' do
    it 'heals only what the lowest Tier allows' do
      before_damage = session.total_hp_damage('Garroth Vask')

      result = session.cast('Heal Petty Wounds', by: 'Sister Auria', on: 'Garroth Vask',
                            dice: [9, 8, 7, 6, 5])

      healed = result.dig('targets', 0, 'applied').find { |a| a['kind'] == 'heal' }['healed']
      expect(healed['minor']).to eq(2)      # Tier 0 minor_damage
      expect(healed['moderate']).to eq(0)   # Tier 0 heals no Moderate
      expect(session.total_hp_damage('Garroth Vask')).to eq(before_damage - 2)
    end

    it 'clears the whole wound at the top of the Tier axis' do
      session.cast('Heal Extreme Wounds', by: 'Sister Auria', on: 'Garroth Vask',
                   dice: [9, 8, 7, 6, 5])

      expect(session.total_hp_damage('Garroth Vask')).to eq(0)
    end

    it 'casts every Heal Tier, each within the amounts its Tier promises' do
      HEAL_TIERS.each do |name, _tier, caps|
        result = session.cast(name, by: 'Sister Auria', on: 'Garroth Vask',
                              dice: [9, 8, 7, 6, 5])

        expect(result['ok']).not_to be(false), "#{name} was refused: #{result['error']}"
        healed = result.dig('targets', 0, 'applied').find { |a| a['kind'] == 'heal' }
        next if healed.nil? # nothing left to heal by the upper Tiers
        caps.each do |severity, cap|
          expect(healed['healed'][severity.to_s].to_i).to be <= cap,
            "#{name} healed more #{severity} damage than its Tier allows"
        end
      end
    end

    it 'drains the bleeding the Heal channel is aimed at' do
      expect(session.afflictions('Garroth Vask')).to have_key('bleeding')

      session.cast('Heal Simple Wounds', by: 'Sister Auria', on: 'Garroth Vask',
                   dice: [9, 9, 9, 9, 9])

      # bleed_reduction is tier*2 per Success; five good dice at Tier 2 is
      # more than the Captain's falchion opened.
      expect(session.afflictions('Garroth Vask')).not_to have_key('bleeding')
    end
  end

  describe 'the ward Spells' do
    it 'grants each Ward Tier the temporary hit points its Tier promises' do
      WARD_TIERS.each do |name, temp_hp|
        result = session.cast(name, by: 'Sister Auria', on: 'Garroth Vask',
                              dice: [9, 8, 7, 6, 5])

        expect(result['ok']).not_to be(false), "#{name} was refused: #{result['error']}"
        applied = result.dig('targets', 0, 'applied').find { |a| a['kind'] == 'temp_hp' }
        expect(applied['amount']).to eq(temp_hp), "#{name} granted #{applied['amount']} temporary hit points"
        expect(session.temp_hp('Garroth Vask')[:amount]).to eq(temp_hp)
      end
    end

    it 'casts a Ward from a Scroll without spending the reader\'s Mana' do
      before_mana = session.mana_spent('Thora Stoneveil')

      result = session.cast('Ward', by: 'Thora Stoneveil', on: 'Garroth Vask',
                            item: true, dice: [9, 8, 7, 6, 5])

      expect(result['item_consumed']).to eq('Scroll of Standard Ward')
      expect(session.mana_spent('Thora Stoneveil')).to eq(before_mana)
      # A Scroll imposes no Item-Form Toxicity — only a Potion does.
      expect(result.dig('toxicity', 'requested')).to eq(0)
    end
  end

  describe 'resources and the clock' do
    it 'debits Mana per cast and accumulates Magic Toxicity' do
      before_mana = session.mana_spent('Sister Auria')
      before_tox  = session.toxicity('Sister Auria')

      session.cast('Standard Ward', by: 'Sister Auria', on: 'Garroth Vask', dice: [9, 8, 7, 6, 5])
      session.cast('Improved Ward', by: 'Sister Auria', on: 'Thora Stoneveil', dice: [9, 8, 7, 6, 5])

      expect(session.mana_spent('Sister Auria')).to be > before_mana
      expect(session.toxicity('Sister Auria')).to be >= before_tox
    end

    it 'moves the campaign clock when the DM steps the out-of-combat Round' do
      before_round = session.scene_round
      before_time  = session.timestamp[:round_of_day]

      session.advance_scene_round
      session.advance_scene_round

      expect(session.scene_round).to eq(before_round + 2)
      expect(session.timestamp[:round_of_day]).to eq(before_time + 2)
    end

    it 'shows the players the campaign clock without giving them the DM page' do
      expect(session.player_get('/dm').status).not_to eq(200)
      expect(session.player_get('/encounter').status).to eq(200)
    end
  end
end
