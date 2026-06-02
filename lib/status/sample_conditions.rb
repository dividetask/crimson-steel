require 'json'

module Status
  # Sample player Creatures and Save Resolution scenarios for the
  # Conditions sub-view of the Status page. Conditions State is drawn
  # from docs/common/conditions/conditions_data.example.json by
  # Creature ID. The four scenarios cover bleed/poison at varying
  # potencies, plus a multi-step Save Resolution (Reroll + Blessing
  # Nudge) that is also reused on the Check Resolution sub-view.
  module SampleConditions
    module_function

    def creatures
      raw = File.read(File.expand_path('../../docs/common/conditions/conditions_data.example.json', __dir__))
      states = JSON.parse(raw)['creatures'] || {}
      [
        { id: '1',  name: 'Bryn Ironvein',  race: 'Dwarf',  klass: 'Fighter',  tier: 3, max_hp: 24, mana_max: 8,  charisma: 8,  attributes: { str: 14, dex: 10, con: 14, int: 9,  wis: 11, cha: 8  },
          consumables: [
            { name: 'Cure Simple Wounds Potion', tier: 1, quantity: 2 },
            { name: 'Minor Recharge Potion',     tier: 0, quantity: 1 }
          ] },
        { id: '2',  name: 'Wisp Trueheart', race: 'Human',  klass: 'Cleric',   tier: 2, max_hp: 30, mana_max: 12, charisma: 14, attributes: { str: 10, dex: 11, con: 12, int: 11, wis: 16, cha: 14 },
          consumables: [
            { name: 'Cure Lesser Wounds Scroll', tier: 2, quantity: 8 },
            { name: 'Cure Simple Wounds Scroll', tier: 1, quantity: 1 }
          ] },
        { id: '3',  name: 'Tana Quickfoot', race: 'Halfling', klass: 'Rogue',  tier: 2, max_hp: 18, mana_max: 6,  charisma: 12, attributes: { str: 9,  dex: 16, con: 11, int: 13, wis: 12, cha: 12 },
          consumables: [
            { name: 'Cure Simple Wounds Potion', tier: 1, quantity: 1 },
            { name: 'Cure Lesser Wounds Potion', tier: 2, quantity: 4 }
          ] },
        { id: '4',  name: 'Selka Embermane', race: 'Tiefling', klass: 'Sorcerer', tier: 1, max_hp: 14, mana_max: 14, charisma: 16, attributes: { str: 8, dex: 12, con: 11, int: 12, wis: 11, cha: 16 },
          consumables: [] }
      ].map { |c| c.merge(state: Conditions::State.load(states[c[:id]])) }
    end

    def save_resolution_examples(catalog)
      ash_luck = {
        creature_ref: nil, creature_name: 'Ash Windmere',
        source_name: 'Bardic Inspiration', direction: 'pos', pool: 5
      }
      selka_blessing = {
        creature_ref: nil, creature_name: 'Selka Embermane',
        source_name: 'Blessing', direction: 'pos', pool: 4
      }

      [
        {
          creature:   { id: '2', name: 'Wisp Trueheart', tier: 2 },
          affliction: { name: 'bleeding', rule: catalog.affliction('bleeding'),
                        potency: 25, inflicter_tier: 3 },
          save_dice: 7, die_size: 10,
          potency_divisor: catalog.potency_divisor,
          reroll_sources: [ash_luck], reroll_label: 'Luck',
          mass_reroll_sources: nil, nudge_sources: nil,
          stub_id: 'save-bleed-t3'
        },
        {
          creature:   { id: '3', name: 'Tana Quickfoot', tier: 2 },
          affliction: { name: 'common_venom', rule: catalog.affliction('common_venom'),
                        potency: 12, inflicter_tier: 1 },
          save_dice: 5, die_size: 10,
          potency_divisor: catalog.potency_divisor,
          reroll_sources: [ash_luck], reroll_label: 'Luck',
          mass_reroll_sources: nil, nudge_sources: nil,
          stub_id: 'save-poison-t1'
        },
        {
          creature:   { id: '2', name: 'Wisp Trueheart', tier: 2 },
          affliction: { name: 'bleeding', rule: catalog.affliction('bleeding'),
                        potency: 8, inflicter_tier: 2 },
          save_dice: 7, die_size: 10,
          potency_divisor: catalog.potency_divisor,
          reroll_sources: nil,
          mass_reroll_sources: nil, nudge_sources: nil,
          stub_id: 'save-bleed-t2-noluck'
        },
        {
          creature:   { id: '2', name: 'Wisp Trueheart', tier: 2 },
          affliction: { name: 'bleeding', rule: catalog.affliction('bleeding'),
                        potency: 15, inflicter_tier: 2 },
          save_dice: 7, die_size: 10,
          potency_divisor: catalog.potency_divisor,
          reroll_sources: [ash_luck], reroll_label: 'Luck',
          mass_reroll_sources: nil,
          nudge_sources: [selka_blessing], nudge_label: 'Blessing',
          stub_id: 'save-bleed-t2-blessing'
        }
      ]
    end
  end
end
