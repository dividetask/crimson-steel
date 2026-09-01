require_relative 'support/session_helpers'

# An Affliction followed from the bite that caused it to the day it
# clears: the round-by-round saves in Combat, the Ability Damage a failed
# save leaves behind, the out-of-combat relief run, and — for a disease
# measured in days rather than Rounds — what the app does not do yet.
RSpec.describe 'Affliction session — the marsh fever', :session do
  before do
    session.exclude_from_combat('Ash Windmere', 'Lira Duskmoor')
    session.dm_get('/encounter')
    @adder = session.spawn_enemy('Marsh Adder', as: 'Marsh Adder')
    session.start_combat
    session.take_turn(@adder)
    # The Bite (Fangs) the `spider` race grants carries spider_venom, and
    # injects Potency equal to the weapon's affliction_potency plus damage.
    session.attack(by: @adder, on: 'Garroth Vask', dice: [10, 10, 9, 9, 8, 8])
    session.take_turn('Garroth Vask')
  end

  describe 'the venom in Combat' do
    it 'rides the bite in as an Affliction with a Potency, due next turn' do
      venom = session.afflictions('Garroth Vask')['spider_venom']
      expect(venom).not_to be_nil
      expect(venom[:potency]).to be > 0
      expect(Encounter.state.pending_afflictions(session.combatant_id('Garroth Vask')))
        .to include('spider_venom')
    end

    it 'burns off when the victim makes the save' do
      result = session.resolve_affliction_save('Garroth Vask',
                                               affliction: 'spider_venom', dois: 3)

      expect(result.dig('result', 'new_potency')).to eq(0)
      expect(session.afflictions('Garroth Vask')).not_to have_key('spider_venom')
      expect(session.conditions_for('Garroth Vask').state.ability_damage).to be_empty
    end

    it 'bites deeper on a failed save — Dexterity damage, and a higher Potency' do
      before_potency = session.afflictions('Garroth Vask')['spider_venom'][:potency]

      result = session.resolve_affliction_save('Garroth Vask',
                                               affliction: 'spider_venom', dois: -3)

      applied = result.dig('result', 'applied')
      expect(applied['kind']).to eq('ability_damage')
      expect(applied['attribute']).to eq('dex')
      expect(session.conditions_for('Garroth Vask').state.ability_damage)
        .to eq(minor: { dex: applied['amount'] })
      expect(session.afflictions('Garroth Vask')['spider_venom'][:potency])
        .to be > before_potency
    end

    it 'reschedules the next save rather than resolving twice in one turn' do
      session.resolve_affliction_save('Garroth Vask', affliction: 'spider_venom', dois: -3)

      venom = session.afflictions('Garroth Vask')['spider_venom']
      expect(venom[:next_resolution_round]).to be > Encounter.state.current_abs_round
      expect(Encounter.state.pending_afflictions(session.combatant_id('Garroth Vask')))
        .not_to include('spider_venom')
    end
  end

  describe 'treating it out of Combat' do
    before do
      session.resolve_affliction_save('Garroth Vask', affliction: 'spider_venom', dois: -3)
      session.end_combat
      session.transcript.scene('The party stops to treat the bite')
    end

    it 'runs the relief simulation to a clear, and charges the time it took' do
      before_clock = session.timestamp[:round_of_day]

      run = session.treat_affliction('Garroth Vask', affliction: 'spider_venom', seed: 42)
      result = run['result']

      expect(result['cleared']).to be true
      expect(result['died']).to be false
      expect(result['rounds']).to be > 0
      expect(session.afflictions('Garroth Vask')).not_to have_key('spider_venom')
      # The relief took game time, and the campaign clock paid for it.
      expect(session.timestamp[:round_of_day]).to eq(before_clock + result['rounds'])
    end

    it 'is deterministic for a given seed, so a scenario can assert its dice' do
      first = session.treat_affliction('Garroth Vask', affliction: 'spider_venom',
                                       seed: 42, commit: false)
      again = session.treat_affliction('Garroth Vask', affliction: 'spider_venom',
                                       seed: 42, commit: false)

      expect(again['result']['log']).to eq(first['result']['log'])
      # A preview changes nothing.
      expect(session.afflictions('Garroth Vask')).to have_key('spider_venom')
    end

    # Garroth shrugs the adder's venom off on the first save, so the aider
    # never has to channel. A Potency that actually bites needs a weaker
    # victim and a higher-Tier source than anything on this roster carries
    # — hence the hand-inflicted dose (see `inflict`).
    it 'brings a Heal channeler in as an aider, at the cost of their Mana' do
      session.include_in_combat('Lira Duskmoor')
      session.inflict('common_venom', on: 'Lira Duskmoor', potency: 60, inflicter_tier: 5)
      before_mana = session.mana_spent('Sister Auria')
      aider = { creature_id: session.creature_id('Sister Auria'), tier: 3 }

      run = session.treat_affliction('Lira Duskmoor', affliction: 'common_venom',
                                     seed: 3, aiders: [aider])

      expect(run['result']['cleared']).to be true
      expect(session.mana_spent('Sister Auria')).to be > before_mana
      # The venom cost Lira hit points on the way out.
      expect(run['result']['hp_damage']['minor']).to be > 0
    end
  end

  # A disease is measured in days, not Rounds: sleeping_sickness in
  # conditions_afflictions.yaml carries `save_frequency: day`. Nothing in
  # the campaign inflicts one, and nothing outside Combat resolves one.
  describe 'a disease measured in days' do
    before do
      session.end_combat
      session.transcript.scene('Three days on the road with a fever')
      session.inflict('sleeping_sickness', on: 'Garroth Vask', potency: 6, inflicter_tier: 2)
    end

    it 'sits on the Creature with a next save one day out' do
      sickness = session.afflictions('Garroth Vask')['sleeping_sickness']
      expect(sickness[:potency]).to eq(6)
      # A day of Rounds ahead, not a Round.
      expect(sickness[:next_resolution_round] - session.absolute_round)
        .to eq(Timekeeping.rounds_per_day)
    end

    it 'resolves its due saves when the campaign clock passes them' do
      gap 'nothing calls Conditions#resolve_due_afflictions outside Combat — ' \
          '/chronicle/advance-time only moves the clock, so a day-frequency ' \
          'Affliction never rolls a save on the road'
      before_potency = session.afflictions('Garroth Vask')['sleeping_sickness'][:potency]

      session.advance_time(days: 3)

      sickness = session.afflictions('Garroth Vask')['sleeping_sickness']
      expect(sickness.nil? || sickness[:potency] != before_potency).to be(true),
        'three days passed and the sickness never rolled a save'
    end

    it 'gives the DM an endpoint for applying an Affliction' do
      gap 'the only things that inflict an Affliction are a weapon that carries ' \
          'one (Bite (Fangs)) and a Spell; a disease, a curse or a trap has to be ' \
          'poked into Conditions by hand — see Session#inflict'
      posts = Sinatra::Application.routes['POST'].map { |r| r.first.to_s }
      expect(posts.grep(/inflict|apply/i)).not_to be_empty
    end

    it 'rolls the overdue saves when the party sleeps it off' do
      gap '/chronicle/rest-night applies Natural Recovery and moves the clock to ' \
          'the next morning, but never resolves the Afflictions whose saves came ' \
          'due overnight'
      before_potency = session.afflictions('Garroth Vask')['sleeping_sickness'][:potency]

      session.rest_night

      sickness = session.afflictions('Garroth Vask')['sleeping_sickness']
      expect(sickness.nil? || sickness[:potency] != before_potency).to be(true),
        'a night passed and the sickness never rolled its save'
    end
  end
end
