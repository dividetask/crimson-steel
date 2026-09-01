require_relative 'support/session_helpers'

# A day in Harrowgate: the party sells what the road turned up, buys what
# it lost, equips it, and spends a few days of downtime before moving on.
# Everything here goes through the Store and Inventory pages a player
# actually uses, from a player's own address as well as the DM's.
RSpec.describe 'City session — a week in Harrowgate', :session do
  before do
    session.exclude_from_combat('Ash Windmere')
    session.dm_get('/encounter')
    session.dm_post('/atlas/set_active_map', map_id: 2)
    session.transcript.scene('Harrowgate — market day')
  end

  describe 'the Store' do
    it 'is open to players as well as the DM' do
      expect(session.dm_get('/store').status).to eq(200)
      expect(session.player_get('/store').status).to eq(200)
    end

    it 'shows the shared party wallet' do
      expect(session.dm_get('/store').body).to include(session.gold('party').to_i.to_s)
    end

    it 'charges a Character their own gold first' do
      before_own   = session.gold('Thora Stoneveil')
      before_party = session.gold('party')

      result = session.buy([{ item: 'Rapier', for: 'Thora Stoneveil', quantity: 1 }])

      expect(result['ok']).to be true
      expect(result['message']).to match(/Rapier/)
      expect(session.gold('Thora Stoneveil')).to eq(before_own - 25)
      expect(session.gold('party')).to eq(before_party) # the party purse is untouched
      expect(session.quantity_of('Rapier', owner: 'Thora Stoneveil')).to eq(1)
    end

    it 'falls back to the party purse when the buyer cannot cover the price' do
      before_party = session.gold('party')
      broke = 'Garroth Vask' # 60 gold to his name

      result = session.buy([{ item: 'Plate mail', for: broke, quantity: 1 }])

      expect(result['ok']).to be true
      expect(session.gold(broke)).to eq(0)
      expect(session.gold('party')).to be < before_party
      expect(session.quantity_of('Plate mail', owner: broke)).to eq(1)
    end

    it 'refuses a cart line naming an Item the catalog does not have' do
      result = session.buy([{ item: 'Vorpal Toothpick', for: 'Thora Stoneveil', quantity: 1 }])

      expect(result['message']).to match(/unknown item/i)
      expect(session.quantity_of('Vorpal Toothpick', owner: 'Thora Stoneveil')).to eq(0)
    end

    it 'restocks the potions the road used up' do
      before_potions = session.quantity_of('Potion of Heal', owner: 'Sister Auria')

      session.buy([{ item: 'Potion of Heal', for: 'Sister Auria', quantity: 2, tier: 2 }])

      expect(session.quantity_of('Potion of Heal', owner: 'Sister Auria'))
        .to eq(before_potions + 2)
    end
  end

  describe 'kitting out' do
    it 'equips what was just bought' do
      session.buy([{ item: 'Breastplate', for: 'Thora Stoneveil', quantity: 1 }])
      creature = session.creature_id('Thora Stoneveil')
      index = session.inventory('Thora Stoneveil').index { |st| st.item_type == 'Breastplate' }

      session.dm_post('/inventory/equip', creature_id: creature, index: index)

      expect(session.inventory('Thora Stoneveil')[index].equipped).to be true
    end

    # Discard drops an Item into the shared Party Inventory (the Sell
    # Pile); the DM's Delete then throws it away for good.
    it 'moves unwanted loot to the Sell Pile and lets the DM clear it' do
      session.buy([{ item: 'Dagger', for: 'Garroth Vask', quantity: 1 }])
      creature = session.creature_id('Garroth Vask')
      index = session.inventory('Garroth Vask').index { |st| st.item_type == 'Dagger' }

      session.dm_post('/inventory/discard', creature_id: creature, index: index)

      expect(session.quantity_of('Dagger', owner: 'Garroth Vask')).to eq(0)
      expect(session.quantity_of('Dagger', owner: 'party')).to eq(1)

      pile_index = session.inventory('party').index { |st| st.item_type == 'Dagger' }
      session.dm_post('/inventory/sell_delete', creature_id: creature, index: pile_index)

      expect(session.quantity_of('Dagger', owner: 'party')).to eq(0)
    end
  end

  describe 'downtime' do
    it 'moves the campaign clock a week without touching Combat' do
      expect(session.combat_active?).to be false
      start_day = session.day_index

      7.times { session.rest_night }

      expect(session.day_index).to eq(start_day + 7)
      expect(session.combat_active?).to be false
    end

    it 'mends the light wounds first over a week in town' do
      captain = session.spawn_enemy('Bandit Captain', as: 'Street Tough')
      session.start_combat
      session.take_turn(captain)
      session.attack(by: captain, on: 'Garroth Vask', dice: [10, 10, 9, 9, 8, 8])
      session.end_combat
      wounded = session.hp_damage('Garroth Vask').dup

      7.times { session.rest_night }

      healed = session.hp_damage('Garroth Vask')
      # Minor damage closes over a week of rest; the Major wound does not.
      expect(healed[:minor].to_i).to eq(0)
      expect(session.total_hp_damage('Garroth Vask')).to be < wounded.values.sum
      expect(healed[:major].to_i).to be > 0
    end
  end

  # What a city visit does not do yet.
  describe 'what a city visit does not track yet' do
    it 'rolls the Shop day over as the campaign clock advances' do
      gap 'Equipment::Shops#advance_time expires each Generic Shop\'s stock on ' \
          'the next Game Day, but nothing calls it — no route, and no hook on ' \
          'the Chronicle clock. The Shop Game Day never moves'
      before_day = Equipment.instance.instance_variable_get(:@game_day)

      3.times { session.rest_night }

      expect(Equipment.instance.instance_variable_get(:@game_day)).to be > before_day
    end

    it 'has a Shop to visit at all, rather than a catalog with prices' do
      gap 'the Store provisions from the whole catalog at Unit Price. The ' \
          'Generic Shop stocking rules in shops.yaml (population-scaled stock, ' \
          'a finite purchasing budget) are loaded but no page visits a Shop'
      routes = Sinatra::Application.routes.values.flatten(1).map { |r| r.first.to_s }
      expect(routes.grep(/shop/i)).not_to be_empty
    end

    it 'takes the old armour off when a new one goes on' do
      gap 'Equipment#equip_stack only flips a flag — nothing enforces Slot ' \
          'exclusivity, so a Character can wear a Chain shirt and a Breastplate ' \
          'at once and reconcile_loadout posts the effects of both'
      session.buy([{ item: 'Breastplate', for: 'Thora Stoneveil', quantity: 1 }])
      creature = session.creature_id('Thora Stoneveil')
      stacks = session.inventory('Thora Stoneveil')
      new_index = stacks.index { |st| st.item_type == 'Breastplate' }
      old_index = stacks.index { |st| st.item_type == 'Chain shirt' }

      session.dm_post('/inventory/equip', creature_id: creature, index: new_index)

      expect(session.inventory('Thora Stoneveil')[old_index].equipped).to be false
    end

    it 'credits gold when the party sells its loot' do
      gap 'the Sell Pile only deletes. Equipment prices every Item and a Shop ' \
          'has a purchasing budget (shop_can_buy?), but no route turns loot ' \
          'into gold'
      session.buy([{ item: 'Dagger', for: 'Garroth Vask', quantity: 1 }])
      creature = session.creature_id('Garroth Vask')
      index = session.inventory('Garroth Vask').index { |st| st.item_type == 'Dagger' }
      session.dm_post('/inventory/discard', creature_id: creature, index: index)
      before_gold = session.gold('party')

      pile_index = session.inventory('party').index { |st| st.item_type == 'Dagger' }
      session.dm_post('/inventory/sell_delete', creature_id: creature, index: pile_index)

      expect(session.gold('party')).to be > before_gold
    end

    it 'charges the party for a week of lodging and food' do
      gap 'no upkeep of any kind: downtime costs nothing, and Rations are ' \
          'never consumed (see the travel session)'
      before_gold = session.gold('party')

      7.times { session.rest_night }

      expect(session.gold('party')).to be < before_gold
    end
  end
end
