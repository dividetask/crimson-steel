require_relative 'support/session_helpers'

# A combat run the way it is run at the table: the DM puts the party and
# the opposition on the tracker, starts Combat, and walks the turn order,
# driving the Cast, Attack and Active Spells panes for each Spell this
# campaign cares about.
#
# The Spells under test are listed once, in COVERED; the guard at the
# bottom fails if one of them never gets cast, so adding a Spell to the
# list is a standing request for a scenario that uses it.
RSpec.describe 'Combat session — ambush on the caravan road', :session do
  COVERED = ['Shield of Faith', 'Standard Shield', 'Spiritual Weapon',
             'Grease', 'Create Pit'].freeze

  # Every Spell this file actually casts, filled in as the scenarios run.
  # The guard example at the bottom reads it, so it must stay last —
  # this suite runs in defined order (no --order in .rspec).
  CAST_IN_SESSION = []

  def cast(spell, **args)
    CAST_IN_SESSION << spell unless CAST_IN_SESSION.include?(spell)
    session.cast(spell, **args)
  end

  def cast_area(spell, **args)
    CAST_IN_SESSION << spell unless CAST_IN_SESSION.include?(spell)
    session.cast_area(spell, **args)
  end

  before do
    # Sister Auria and Ash are elsewhere this scene. Without the toggle the
    # Encounter page reconciles every Player Character onto the roster.
    session.exclude_from_combat('Sister Auria', 'Ash Windmere')
    session.add_to_roster('Thora Stoneveil', 'Lira Duskmoor', 'Garroth Vask')
    @raider = session.spawn_enemy('Goblin Raider', as: 'Goblin Raider A')
    @archer = session.spawn_enemy('Goblin Archer', as: 'Goblin Archer B')
    session.start_combat
  end

  it 'rolls Initiative for everyone on the tracker when Combat starts' do
    expect(session.combat_active?).to be true
    expect(Encounter.state.combatants.map { |c| c[:initiative_string] })
      .to all(satisfy { |s| !s.to_s.empty? })
    # The DM's excluded Player Characters stayed off the roster.
    expect(session.initiative_order).not_to include('Sister Auria')
  end

  describe 'Shield of Faith' do
    it 'fills a Reservoir on the caster rather than striking the target' do
      session.take_turn('Thora Stoneveil')
      mana_before = session.mana_spent('Thora Stoneveil')

      result = cast('Shield of Faith', by: 'Thora Stoneveil', on: 'Garroth Vask',
                    dice: [9, 8, 3, 7, 2])

      expect(result['ok']).not_to be false
      expect(result.dig('sustain', 'kind')).to eq('concentration')
      expect(result.dig('sustain', 'reservoir')).to be > 0
      # The cast is a buff: Garroth takes nothing from being shielded.
      expect(session.total_hp_damage('Garroth Vask')).to eq(0)
      # Tier 1 Mana came out of Thora's pool.
      expect(session.mana_spent('Thora Stoneveil')).to be > mana_before
      # The shield is held as a Concentration entry on the caster, not as a
      # condition on the ally.
      held = session.combatant('Thora Stoneveil')[:concentration]
                    .find { |e| e[:spell_name] == 'Shield of Faith' }
      expect(held[:mode]).to eq('reservoir')
    end

    it 'is spent as an Ally Defense when the shielded ally is attacked' do
      session.take_turn('Thora Stoneveil')
      cast('Shield of Faith', by: 'Thora Stoneveil', on: 'Garroth Vask',
           dice: [9, 8, 3, 7, 2])
      reservoir_before = session.combatant('Thora Stoneveil')[:concentration]
                                .find { |e| e[:spell_name] == 'Shield of Faith' }[:reservoir]

      session.take_turn(@raider)
      result = session.attack(by: @raider, on: 'Garroth Vask', dice: [9, 8, 7, 6, 5],
                              shielded_by: 'Thora Stoneveil', shield_dice: [9, 9, 8])

      expect(result['ok']).not_to be false
      # The interposed shield opposed the attack: the strike nets down.
      expect(result['net_dos']).to be < 5
      spent = session.combatant('Thora Stoneveil')[:concentration]
                     .find { |e| e[:spell_name] == 'Shield of Faith' }
      expect(spent[:reservoir]).to be < reservoir_before
    end
  end

  describe 'Standard Shield' do
    it 'conjures a shield with no Reservoir, blocked with Combat Pool dice' do
      session.take_turn('Lira Duskmoor')
      result = cast('Standard Shield', by: 'Lira Duskmoor', on: 'Lira Duskmoor',
                    dice: [9, 8, 7, 6, 2])

      expect(result['ok']).not_to be false
      # Unlike Shield of Faith, nothing is charged at cast.
      expect(result.dig('sustain', 'reservoir')).to be_nil
    end

    it 'interposes for the caster when they are attacked' do
      session.take_turn('Lira Duskmoor')
      cast('Standard Shield', by: 'Lira Duskmoor', on: 'Lira Duskmoor',
           dice: [9, 8, 7, 6, 2])

      session.take_turn(@raider)
      result = session.attack(by: @raider, on: 'Lira Duskmoor', dice: [9, 8, 7, 6, 5],
                              shielded_by: 'Lira Duskmoor', shield_dice: [9, 8, 8])

      expect(result['ok']).not_to be false
      expect(result['net_dos']).to be < 5
    end
  end

  describe 'Spiritual Weapon' do
    it 'only conjures the weapon on cast — the strike is a separate action' do
      session.take_turn('Thora Stoneveil')
      result = cast('Spiritual Weapon', by: 'Thora Stoneveil', dice: [9, 8, 7, 6, 2])

      expect(result.dig('sustain', 'spell_name')).to eq('Spiritual Weapon')
      expect(result.dig('sustain', 'reservoir')).to eq(5)
      expect(result['targets']).to be_empty
    end

    it 'strikes through the Active Spells pane, netting against a Dodge' do
      session.take_turn('Thora Stoneveil')
      cast('Spiritual Weapon', by: 'Thora Stoneveil', dice: [9, 8, 7, 6, 2])

      result = session.strike_with('Spiritual Weapon', by: 'Thora Stoneveil',
                                   on: @raider, dice: [9, 8, 7, 6, 5])

      expect(result['ok']).not_to be false
      expect(result['damage']).to be > 0
      expect(session.total_hp_damage(@raider)).to eq(result['damage'])
      # The Reservoir is not consumed by striking — it is the weapon's dice.
      held = session.combatant('Thora Stoneveil')[:concentration]
                    .find { |e| e[:spell_name] == 'Spiritual Weapon' }
      expect(held[:reservoir]).to eq(5)
    end
  end

  describe 'Grease' do
    it 'drops a failed target prone when cast on them as an object' do
      session.take_turn('Lira Duskmoor')
      result = cast('Grease', by: 'Lira Duskmoor', on: @raider,
                    dice: [9, 8, 7, 6, 2], save_dice: [3, 4, 2, 1])

      expect(result['ok']).not_to be false
      expect(session.effect_names(@raider)).to include('prone')
    end
  end

  describe 'Create Pit' do
    it 'places a Zone on the Atlas and drops those who fail the Save into it' do
      session.take_turn('Lira Duskmoor')
      result = cast_area('Create Pit', by: 'Lira Duskmoor', at: { x: 4, y: 4 },
                         affecting: { @raider => [3, 4, 2, 1] },
                         dice: [9, 8, 7, 6, 2])

      expect(result['ok']).not_to be false
      expect(result.dig('zone', 'shape')).to eq('square')
      expect(result.dig('zone', 'map_id')).to eq(1) # the active Map
      expect(session.effect_names(@raider)).to include('in_pit')
    end

    # Worth reading with the transcript open: the dice barely matter here.
    # A Tier-0 goblin saving against a Tier-2 wizard has the caster's
    # Competency, Inherent and Guidance bonuses crossed onto its own Roll as
    # penalties, which clamps its TN to the configured maximum and turns the
    # overflow into Starting Failures — four dice including two Criticals
    # still come out negative.
    it 'cannot be saved against by a Creature far below the caster in Tier' do
      session.take_turn('Lira Duskmoor')
      cast_area('Create Pit', by: 'Lira Duskmoor', at: { x: 8, y: 8 },
                affecting: { @archer => [10, 10, 9, 9] }, # two Criticals
                dice: [4, 3, 2, 2, 1])                    # against a poor cast

      expect(session.effect_names(@archer)).to include('in_pit')
    end

    it 'is saved against easily by a Creature well above the caster in Tier' do
      session.include_in_combat('Sister Auria') # Tier 5, against a Tier 2 caster
      session.take_turn('Lira Duskmoor')
      cast_area('Create Pit', by: 'Lira Duskmoor', at: { x: 8, y: 8 },
                affecting: { 'Sister Auria' => [10, 9, 8, 8, 7, 7] },
                dice: [4, 3, 2, 2, 1])

      expect(session.effect_names('Sister Auria')).not_to include('in_pit')
    end
  end

  describe 'healing and warding mid-combat' do
    it 'heals damage by Severity and clears the bleed the axe opened' do
      session.take_turn('Garroth Vask')
      session.attack(by: 'Garroth Vask', on: @raider, dice: [9, 8, 7, 6, 5, 4])
      expect(session.total_hp_damage(@raider)).to be > 0

      session.take_turn('Thora Stoneveil')
      result = cast('Heal Lesser Wounds', by: 'Thora Stoneveil', on: @raider,
                    dice: [9, 8, 7, 6, 5])

      applied = result.dig('targets', 0, 'applied')
      heal = applied.find { |a| a['kind'] == 'heal' }
      expect(heal['healed']['minor']).to be > 0
      # The Heal channel also drains bleeding — tier*2 per Success.
      expect(applied.map { |a| a['kind'] }).to include('bleed_reduction')
    end

    it 'grants the Ward temporary hit points its Tier promises' do
      session.take_turn('Thora Stoneveil')
      cast('Standard Ward', by: 'Thora Stoneveil', on: 'Garroth Vask',
           dice: [9, 8, 7, 6, 5])

      # Ward's temp_hp table is [3, 5, 8, 12, 16, 20] by Tier; Standard is Tier 2.
      expect(session.temp_hp('Garroth Vask')[:amount]).to eq(8)
    end
  end

  # The list is the contract: a Spell named in COVERED that no scenario in
  # this file casts is a hole in the coverage, not a passing suite. This
  # lives in a trailing group because RSpec runs a group's own examples
  # before its nested groups — as a bare `it` it would run first, before
  # anything had been cast.
  describe 'coverage' do
    it 'casts every Spell the project asked this session to cover' do
      missing = COVERED - CAST_IN_SESSION
      expect(missing).to be_empty,
        "no scenario in this file casts: #{missing.join(', ')}"
    end
  end
end
