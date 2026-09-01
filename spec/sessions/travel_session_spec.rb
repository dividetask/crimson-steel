require_relative 'support/session_helpers'

# Four days on the road: the DM moves the party between Maps, jumps the
# clock by hours and by days, runs a wandering encounter, and camps each
# night. This is the scenario where the campaign clock does the work, so
# it is also where the things the clock does *not* yet drive show up.
RSpec.describe 'Travel session — four days to Harrowgate', :session do
  before do
    session.exclude_from_combat('Ash Windmere')
    session.dm_get('/encounter')
    session.transcript.scene('Day 0 — the party leaves the caravan road')
  end

  describe 'the campaign clock' do
    it 'jumps by hours without rolling the day over' do
      start_day = session.day_index
      # Four hours of walking, in Rounds.
      rounds_per_hour = Timekeeping.rounds_per_day / 24
      session.advance_time(rounds: rounds_per_hour * 4)

      expect(session.day_index).to eq(start_day)
      expect(session.time_of_day).to eq('12:00:00') # camp broke at 08:00
    end

    it 'jumps by days, and the calendar follows' do
      before_date = session.calendar_date
      session.advance_time(days: 4)

      expect(session.day_index).to eq(4)
      expect(session.calendar_date[:day_of_month])
        .to eq(before_date[:day_of_month] + 4)
      expect(session.calendar_date[:day_of_week]).not_to eq(before_date[:day_of_week])
    end

    it 'rolls hours past midnight into the next day' do
      session.advance_time(rounds: Timekeeping.rounds_per_day)

      expect(session.day_index).to eq(1)
      expect(session.time_of_day).to eq('08:00:00')
    end
  end

  describe 'camping' do
    before do
      # Something to recover from: only the Tier-2 Captain can mark a
      # Tier-2 Character.
      @captain = session.spawn_enemy('Bandit Captain', as: 'Bandit Captain')
      session.start_combat
      session.take_turn(@captain)
      session.attack(by: @captain, on: 'Garroth Vask', dice: [10, 10, 9, 9, 8, 8])
      session.end_combat
    end

    it 'mends damage overnight and wakes the party at dawn' do
      wounded = session.total_hp_damage('Garroth Vask')
      expect(wounded).to be > 0

      session.rest_night

      expect(session.total_hp_damage('Garroth Vask')).to be < wounded
      expect(session.day_index).to eq(1)
      expect(session.time_of_day).to eq('08:00:00')
    end

    it 'mends a little more each night on the road' do
      night_one = session.total_hp_damage('Garroth Vask')
      session.rest_night
      night_two = session.total_hp_damage('Garroth Vask')
      session.rest_night

      expect(session.total_hp_damage('Garroth Vask')).to be < night_two
      expect(night_two).to be < night_one
      expect(session.day_index).to eq(2)
    end
  end

  describe 'the Atlas' do
    it 'moves the party from the road to the city gate' do
      road = Atlas.state.active_map_id
      session.dm_post('/atlas/set_active_map', map_id: 2)

      expect(Atlas.state.active_map_id).to eq(2)
      expect(Atlas.state.active_map_id).not_to eq(road)
      expect(Atlas.state.get_map(2)[:name]).to eq('Harrowgate')
    end
  end

  describe 'a wandering encounter' do
    it 'rolls a table whose templates this Campaign carries' do
      before_roster = Encounter.state.combatants.length

      res = session.dm_get('/random_encounters/roll/general_goblin_ambush')

      expect(res.status).to eq(200)
      expect(res.body).to match(/Goblin/)
      # Every spawn lands on the tracker, equipped from its loadout.
      expect(Encounter.state.combatants.length).to be > before_roster
    end

    it 'says which templates are missing rather than spawning half a table' do
      before_roster = Encounter.state.combatants.length

      # The Random Encounter Tables ship in docs/common and name their
      # Creatures by id; this Campaign carries none of the Slave Lords ids.
      res = session.dm_get('/random_encounters/roll/slave_lords_caravan')

      expect(res.status).to eq(200)
      expect(res.body).to match(/aren't in your data/)
      expect(Encounter.state.combatants.length).to eq(before_roster)
    end

    it 'runs a hand-placed ambush on the third day' do
      session.advance_time(days: 3)
      session.transcript.scene('Day 3 — goblins at the ford')
      raider = session.spawn_enemy('Goblin Raider', as: 'Ford Raider')
      session.start_combat
      session.take_turn('Garroth Vask')

      result = session.attack(by: 'Garroth Vask', on: raider, dice: [9, 8, 7, 6, 5, 4])

      expect(result['damage']).to be > 0
      expect(session.day_index).to eq(3)
    end
  end

  # What the road does not do yet. Each of these is written as the
  # behavior a travel session wants; none of it exists.
  describe 'what travel does not track yet' do
    def creature_name_of(combatant)
      rec = Creatures::Dataset.get(combatant[:creature_id])
      rec ? rec[:name] : combatant[:creature_id].to_s
    end

    it 'consumes the party Rations for each day travelled' do
      gap 'nothing in the app reads or decrements Rations — the Item is in ' \
          'the catalog and in inventories, but no route consumes it as time passes'
      before_rations = session.quantity_of('Rations', owner: 'party')

      session.advance_time(days: 4)

      expect(session.quantity_of('Rations', owner: 'party')).to eq(before_rations - 4)
    end

    it 'applies Natural Recovery for the days a jump skipped over' do
      gap '/chronicle/advance-time only moves the clock. Natural Recovery runs ' \
          'from /chronicle/rest-night, one tick per press, so a four-day jump ' \
          'mends nothing — the DM has to press Rest four times'
      captain = session.spawn_enemy('Bandit Captain', as: 'Ambusher')
      session.start_combat
      session.take_turn(captain)
      session.attack(by: captain, on: 'Garroth Vask', dice: [10, 10, 9, 9, 8, 8])
      session.end_combat
      wounded = session.total_hp_damage('Garroth Vask')

      session.advance_time(days: 4)

      expect(session.total_hp_damage('Garroth Vask')).to be < wounded
    end

    it 'lets a scenario seed a random encounter roll' do
      gap '/random_encounters/roll/:table_id ignores a seed, though ' \
          'Creatures.roll_random_encounter accepts one — so a rolled encounter ' \
          'cannot be replayed, by the DM or by a Session Test'
      spawns = lambda do
        session.dm_get('/random_encounters/roll/general_goblin_ambush')
        Encounter.state.combatants.map { |c| creature_name_of(c) }.tally
      end

      expect(spawns.call).to eq(spawns.call)
    end

    it 'has any notion of travel pace or distance covered in a day' do
      gap 'there is no travel domain: no pace, no distance per day, no route ' \
          'between Maps. A journey is the DM pressing Advance Time and ' \
          'describing it out loud'
      routes = Sinatra::Application.routes.values.flatten(1).map { |r| r.first.to_s }
      expect(routes.grep(/travel|journey|pace/i)).not_to be_empty
    end
  end
end
