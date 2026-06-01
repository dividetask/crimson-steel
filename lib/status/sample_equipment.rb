module Status
  # Sample Equipment Store data for the Equipment sub-view of the Status
  # page. Per the project's per-page-data rule this is hand-curated dummy
  # data for the Status page only — never a window into a live Shop (that
  # lives on /store via Equipment's Visit Generic Shop). The hash matches
  # the locals the Equipment Store Stub consumes (see
  # views/_equipment_store_stub.erb and
  # docs/common/ui/equipment_store_stub.md).
  #
  # `purchasable: false` renders the stub as an inert preview: the
  # shop/buyer selectors and Buy buttons are disabled, so the panel emits
  # no real state changes.
  module SampleEquipment
    module_function

    def store
      cs = cards
      {
        viewer:       :dm,
        purchasable:  false,
        total_wealth: 128,
        buyers:       [{ id: 1, name: 'Bryn' }, { id: 2, name: 'Ash' }, { id: 3, name: 'Veyl' }],
        buyer_id:     1,
        shops:        [{ id: 'weapons_shop', name: 'Weapons Shop' },
                       { id: 'alchemist_shop', name: 'Alchemist Shop' }],
        shop_id:      'weapons_shop',
        shop_name:    'Weapons Shop',
        flash:        nil,
        cards:        cs,
        categories:   cs.map { |c| c[:category] }.uniq.sort,
        tiers:        cs.map { |c| c[:tier] }.uniq.sort
      }
    end

    # A representative spread of buyable Stacks: mundane and magical
    # weapons, ammunition with a fractional unit price, armor, and tiered
    # consumables — enough to exercise the Tier badge, the Property line,
    # the description line, and both Category and Tier filters.
    def cards
      @cards ||= [
        card(0, 'Dagger',                 'Weapon',     0, 2),
        card(1, 'Long sword',             'Weapon',     0, 15),
        card(2, '+1 Flaming Long sword',  'Weapon',     1, 320, properties: 'Flaming',
             description: 'Wreathed in fire that licks along the blade.'),
        card(3, 'Arrow',                  'Ammunition', 0, 0.05, available: 120),
        card(4, 'Leather armor',          'Armor',      0, 10),
        card(5, 'Healing Potion',         'Consumable', 0, 50, available: 12),
        card(6, '+2 Healing Potion',      'Consumable', 2, 1000, available: 1)
      ]
    end

    def card(index, name, category, tier, price, properties: '', description: nil, available: 3)
      { index: index, display_name: name, category: category, tier: tier,
        properties: properties, description: description, unit_price: price,
        available: available }
    end
  end
end
