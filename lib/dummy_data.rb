require 'json'

# Dummy data for the Status page sub-views. The page is fed example
# Rolls / Checks / Creatures so the stubs can render without a real
# Combat or Creatures domain wired in.
module DummyData
  module_function

  # ---------- Timekeeping ----------

  # Six Timestamps that exercise the Timekeeping Stub: early morning,
  # dawn, midday, dusk, midnight, plus a Leap Day for Calendar Date
  # variety.
  def timekeeping_examples
    rpd = Timekeeping.rounds_per_day
    [
      { label: 'Early morning', timestamp: { day_index: 731, round_of_day: rpd / 4 } },
      { label: 'Dawn',          timestamp: { day_index: 732, round_of_day: 3600 } },
      { label: 'Midday',        timestamp: { day_index: 732, round_of_day: rpd / 2 } },
      { label: 'Dusk',          timestamp: { day_index: 732, round_of_day: rpd * 3 / 4 } },
      { label: 'Midnight',      timestamp: { day_index: 733, round_of_day: 0 } },
      { label: 'Leap Day demo', timestamp: { day_index: 789, round_of_day: rpd / 2 } }
    ]
  end

  # ---------- Chronicle ----------

  # Five example Entries for the Chronicle sub-view of the Status
  # page. Intentionally divorced from the live example Campaign in
  # chronicle_data.example.json so reviewers don't confuse the two.
  # The Status sub-view renders the same five Entries twice — once
  # under the DM viewer role, once under a player viewer (Bryn,
  # Creature id 1) — so the role differences are easy to compare.
  def chronicle_examples
    hollow_glade = {
      id: 9001, entry_type: 'note', chapter: 1,
      notes_position: 1, scene_position: 1,
      title: 'Briefing — The Hollow Glade',
      public_description: "Three travelers vanished from the Hollow Glade trail this month. The ranger station marked the trees with white chalk where each disappearance happened — the chalk is gone now, but you can still feel where the bark was scraped. Local hunters refuse to cross the glade after dark and the lumber camp has stopped sending crews past the second bridge.\n\nThe rangers found two of the packs intact and untouched in clearings several leagues apart. The third pack has not been found; the traveler in question, a tinker from a coastal town to the south, was carrying a brass ledger he claimed had been promised to a man in the next valley. The ledger has not turned up either.\n\nA child from the nearby farm holding swears she saw a tall figure with no face walking among the trees the morning after the third disappearance. Adults dismiss the story. The party may want to talk to her before her parents decide otherwise.",
      dm_description: 'The vanishings line up with new-moon nights. The Lantern is hunting at the edge of the glade and dragging the bodies into the cliffs.',
      image: '/example_images/saltmere_lighthouse.svg',
      shared: true, hidden_from: [], owner_id: nil, active: true
    }
    dm_secret = {
      id: 9002, entry_type: 'note', chapter: 1,
      notes_position: 2, scene_position: 2,
      title: 'GM — Behind the Curtain',
      public_description: '',
      dm_description: "The Pale Lantern was not always pale. In life it was a keeper named Iren Halverlight, drowned in 4691 trying to reach a foundering ship he had inadvertently lured onto the rocks with a beacon he had been told to keep dark. The oath that binds him to the spire is the one he never finished — to confess to the harbormaster what had happened. Daven Korr already knows the story; the merchants' guild does not.\n\nPlot pivots:\n- If the party releases the Lantern by completing the oath on his behalf (a Diplomacy check vs Daven), the beacon goes out permanently and the coast stays vulnerable. Daven offers them the keeper's salary anyway.\n- If the party binds the Lantern to the new beacon stone (an Arcana check at the watchroom), the beacon relights and the haunting eases but the Lantern persists, only quieter.\n- If the party destroys the Lantern outright, the beacon lights and stays lit, but every keeper who tries to live in the spire from then on dies inside a month. This is a story consequence; the party will not learn of it until much later.\n\nDaven will not lie about the Lantern's identity if asked directly. He will not volunteer it.",
      image: nil, shared: false, hidden_from: [], owner_id: nil, active: false
    }
    spiral_stair = {
      id: 9003, entry_type: 'note', chapter: 3,
      notes_position: 3, scene_position: 3,
      title: 'The Spiral Stair',
      public_description: "The lighthouse spire has 247 iron steps and not one of them is level. Halfway up, the wall is scored with seven long parallel grooves at shoulder height. Cold air pours from above, even at midday.\n\nTana counted the steps twice on the way up and got a different total each time — 247 the first count, 251 the second. She blamed the wind. Bryn counted them on the way back down and got 247 twice in a row, but he insisted the landings had moved between counts. Selka refused to count and stared at the wall instead.\n\nThe grooves run for about thirty paces along the inner wall, then stop in clean iron, as if something had hit the metal and decided to leave through it instead of around it. The air on the upper side of the grooves is roughly a fingerwidth colder than the air on the lower side. You can feel the difference if you sit very still with one hand above the line and one below.\n\nThe keeper's logbook, recovered at the watchroom landing on Day Four, records two earlier incidents in the same place. Both entries end mid-sentence. Both have the same word scratched into the margin in a different hand than the rest: \"wait\".\n\nThe party did not wait.",
      dm_description: "The grooves are claw marks, but not from any beast the players will recognize. Strictly speaking, they are not claw marks at all — they are a record of motion preserved in iron, like a stonemason's mark of an animal that wasn't yet born. The Pale Lantern leaves them whenever it descends; the temperature differential is its trail.\n\nIf the party rests on the steps between the grooves and the watchroom, run the long-rest table with one column shifted toward Cold instead of Quiet.",
      image: nil, shared: true, hidden_from: [], owner_id: nil, active: true
    }
    pale_lantern = {
      id: 9004, entry_type: 'creature', chapter: 4,
      notes_position: 4, scene_position: 4,
      title: '',
      public_description: 'A figure of cold blue light glimpsed at the top of the spire. Where it walks the lamps gutter and the iron rusts. It does not speak.',
      dm_description: '',
      image: '/example_images/pale_lantern.svg',
      shared: true, hidden_from: [], owner_id: nil, active: true,
      creature_id: 1003, creature_token: nil, tier: 4
    }
    bryn_journal = {
      id: 9005, entry_type: 'note', chapter: 1,
      notes_position: 5, scene_position: 5,
      title: "Bryn's Field Journal",
      public_description: "Day Seven on the coast. The wind off the water tastes like iron and old kelp. I have started counting my own pulses while I sleep — Tana's idea. She says it keeps the cold from getting inside you. I cannot tell if she is right or if I am just sleeping badly.\n\nWisp has been quieter than usual. She watched the watchroom door for two hours last night without speaking, then asked me whether I trust the harbormaster. I told her the truth, which is that I do not, but I trust the work. She nodded and went back to looking at the door.\n\nSelka's water-skin froze on the stair on Day Four. She has not let any of us touch it since. I think she is keeping it as a reminder, but a reminder of what I cannot say.\n\nTomorrow we climb again. I have written this in case I do not come back, and I have left it in the dry-box at the foot of the stair. If you are reading it and I am not present, tell Daven I asked after his daughter.",
      dm_description: '',
      image: nil, shared: true, hidden_from: [], owner_id: 1, active: false
    }

    [
      { label: 'Shared note (long public)',         entry: hollow_glade },
      { label: 'Private GM note (long DM only)',    entry: dm_secret },
      { label: 'Shared note (long public + GM)',    entry: spiral_stair },
      { label: 'Creature reference',                entry: pale_lantern },
      { label: "Player-owned note (Bryn, shared)",  entry: bryn_journal }
    ]
  end

  def rolls
    [
      {
        creature_name: 'Orc Patrol',
        roll_name: 'Attack (Greataxe)',
        dice_count: 3, tn: 5, starting_value: 0,
        reroll: nil,
        nudge:  nil,
        initial_dice: [2, 5, 6],
        post_reroll_dice: nil,
        post_nudge_dice: nil,
        dois: 2, critical_count: 1, die_size: 10
      },
      {
        creature_name: 'Bryn Ironvein',
        roll_name: 'Attack (Longsword)',
        dice_count: 8, tn: 3, starting_value: 2,
        reroll: { amount: 2, max: false, sign: :neg, label: 'Unsettling Words' },
        nudge:  nil,
        initial_dice: [8, 6, 10, 1, 10, 4, 8, 10],
        post_reroll_dice: [nil, nil, nil, nil, 9, nil, nil, 1],
        post_nudge_dice: nil,
        dois: 9, critical_count: 1, die_size: 10
      },
      {
        creature_name: 'Wisp Familiar',
        roll_name: 'Aid (Guidance)',
        dice_count: 4, tn: 5, starting_value: 1,
        reroll: { amount: 1, max: false, sign: :pos, label: 'Bardic Inspiration' },
        nudge:  { amount: 1, max: false, sign: :pos, label: 'Guidance' },
        initial_dice: [1, 3, 5, 8],
        post_reroll_dice: [1, 5, 5, 8],
        post_nudge_dice: [1, 5, 6, 9],
        dois: 4, critical_count: 0, die_size: 10
      },
      {
        creature_name: 'Cleric of Ruin',
        roll_name: 'Smite (Curse of Doubt)',
        dice_count: 6, tn: 4, starting_value: 0,
        reroll: nil,
        mass_reroll: { sign: :neg, label: 'Curse of Doubt' },
        nudge:  nil,
        initial_dice: [5, 8, 2, 6, 9, 3],
        post_reroll_dice: nil,
        post_mass_reroll_dice: [3, 7, nil, 2, 4, nil],
        post_nudge_dice: nil,
        dois: 1, critical_count: 0, die_size: 10
      },
      {
        creature_name: 'Frenzied Berserker',
        roll_name: 'Attack (Reckless)',
        dice_count: 10, tn: 5, starting_value: -1,
        reroll: nil,
        mass_reroll: { sign: :pos, label: 'Reckless' },
        nudge:  nil,
        initial_dice: [1, 2, 4, 5, 7, 3, 6, 1, 8, 4],
        post_reroll_dice: nil,
        post_mass_reroll_dice: [nil, nil, nil, 5, 7, nil, 6, nil, 8, nil],
        post_nudge_dice: nil,
        dois: 4, critical_count: 0, die_size: 10
      }
    ]
  end

  def check
    {
      supporting: [
        {
          creature_name: 'Bryn Ironvein',
          roll_name: 'Attack (Longsword)',
          dice_count: 8, tn: 3, starting_value: 1,
          reroll: { amount: 2, max: false, sign: :neg, label: 'Unsettling Words' },
          nudge: nil,
          initial_dice: [10, 8, 7, 4, 8, 4, 6, 9],
          post_reroll_dice: [7, nil, nil, nil, nil, nil, nil, 10],
          post_nudge_dice: nil,
          dois: 9, critical_count: 1, die_size: 10
        },
        {
          creature_name: 'Shield of Faith',
          roll_name: 'Aid',
          dice_count: 5, tn: 6, starting_value: 0,
          reroll: { amount: 1, max: false, sign: :neg, label: 'Unsettling Words' },
          nudge: nil,
          initial_dice: [4, 5, 3, 8, 1],
          post_reroll_dice: [nil, nil, nil, 3, nil],
          post_nudge_dice: nil,
          dois: -1, critical_count: 0, die_size: 10
        }
      ],
      opposing: [
        {
          creature_name: 'Bandit Captain',
          roll_name: 'Dodge',
          dice_count: 6, tn: 6, starting_value: 0,
          reroll: { amount: 3, max: false, sign: :pos, label: 'Bardic Inspiration' },
          nudge: nil,
          initial_dice: [5, 9, 8, 1, 10, 6],
          post_reroll_dice: [nil, nil, nil, 9, nil, nil],
          post_nudge_dice: nil,
          dois: 6, critical_count: 1, die_size: 10
        }
      ]
    }
  end

  # Sample player Creatures. The Conditions State is drawn from
  # docs/common/conditions/conditions_data.example.json by Creature ID.
  def creatures
    raw = File.read(File.expand_path('../docs/common/conditions/conditions_data.example.json', __dir__))
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

  # Four example Conditions Save Resolution scenarios. The first
  # three live on the Conditions sub-view; the fourth (with both a
  # Reroll source and a Blessing Nudge source) is shared between the
  # Conditions and Check Resolution sub-views as a demo of the
  # multi-step Save Resolution Stub.
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
        save_dice: 7, save_tn: 8, die_size: 10,
        potency_divisor: catalog.potency_divisor,
        reroll_sources: [ash_luck], reroll_label: 'Luck',
        mass_reroll_sources: nil, nudge_sources: nil,
        stub_id: 'save-bleed-t3'
      },
      {
        creature:   { id: '3', name: 'Tana Quickfoot', tier: 2 },
        affliction: { name: 'common_venom', rule: catalog.affliction('common_venom'),
                      potency: 12, inflicter_tier: 1 },
        save_dice: 5, save_tn: 6, die_size: 10,
        potency_divisor: catalog.potency_divisor,
        reroll_sources: [ash_luck], reroll_label: 'Luck',
        mass_reroll_sources: nil, nudge_sources: nil,
        stub_id: 'save-poison-t1'
      },
      {
        creature:   { id: '2', name: 'Wisp Trueheart', tier: 2 },
        affliction: { name: 'bleeding', rule: catalog.affliction('bleeding'),
                      potency: 8, inflicter_tier: 2 },
        save_dice: 7, save_tn: 7, die_size: 10,
        potency_divisor: catalog.potency_divisor,
        reroll_sources: nil,
        mass_reroll_sources: nil, nudge_sources: nil,
        stub_id: 'save-bleed-t2-noluck'
      },
      {
        creature:   { id: '2', name: 'Wisp Trueheart', tier: 2 },
        affliction: { name: 'bleeding', rule: catalog.affliction('bleeding'),
                      potency: 15, inflicter_tier: 2 },
        save_dice: 7, save_tn: 7, die_size: 10,
        potency_divisor: catalog.potency_divisor,
        reroll_sources: [ash_luck], reroll_label: 'Luck',
        mass_reroll_sources: nil,
        nudge_sources: [selka_blessing], nudge_label: 'Blessing',
        stub_id: 'save-bleed-t2-blessing'
      }
    ]
  end
end
