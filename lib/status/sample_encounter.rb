module Status
  # Sample Combat Tracker scenarios for the Encounter sub-view of the
  # Status page. Per the project's per-page-data rule this is
  # hand-curated dummy data for the Status page only — never a window
  # into the live Encounter roster (that lives on /encounter via
  # build_tracker_row). The rows match the shape the Encounter
  # Initiative Stub consumes (see views/_initiative_stub.erb and
  # docs/common/ui/encounter_initiative_stub.md).
  #
  # The four scenarios exercise the stub's display axes side-by-side:
  #   - viewer :dm vs :player (Turn column, controls, editable Init).
  #   - combat_active true (End Combat button) vs false (Start Combat).
  #   - rows covering the acting highlight, a cannot-act row, layered
  #     HP damage segments, condition badges, near/over Toxicity
  #     threshold, and a freshly-spawned row whose vitals aren't rolled
  #     yet (dashes).
  #   - an empty roster (the "no combatants" message).
  module SampleEncounter
    module_function

    # The full list of Combat Tracker demos, in display order.
    def scenarios
      shared = roster
      [
        { label: 'DM view — Combat active',
          viewer: :dm, combat_active: true, round_label: 'Round 3', rows: shared },
        { label: 'Player view — Combat active',
          viewer: :player, combat_active: true, round_label: 'Round 3', rows: shared },
        { label: 'DM view — before Combat (Start Combat control)',
          viewer: :dm, combat_active: false, round_label: nil, rows: shared },
        { label: 'DM view — empty roster',
          viewer: :dm, combat_active: false, round_label: nil, rows: [] }
      ]
    end

    # A representative roster in Initiative order (descending). Each row
    # mirrors lib/routes/encounter.rb#build_tracker_row.
    def roster
      [
        # Acting Combatant: layered Minor + Moderate HP damage, mana and
        # Combat Pool partly spent, Toxicity well under threshold.
        row(1, 101, 'Ash Windmere', '9742', acting: true,
            hp: hp(48, current: 38, minor: 4, moderate: 6),
            mana: { remaining: 9, max: 31 },
            toxicity: { value: 0, threshold: 11 },
            combat_pool: { remaining: 3, max: 5 }),

        # Toxicity one point under threshold, a Bleed affliction badge.
        row(2, 109, 'Veyl Aetheris', '8631',
            hp: hp(22, current: 16, minor: 2, moderate: 4),
            mana: { remaining: 12, max: 16 },
            toxicity: { value: 6, threshold: 7 },
            combat_pool: { remaining: 4, max: 6 },
            badges: [badge('bleed', 'Bleed: 3')]),

        # Enemy with Major damage and counters; non-caster, so Mana and
        # Toxicity render as dashes.
        row(3, 303, 'Goblin Archer', '7520',
            hp: hp(11, current: 4, moderate: 3, major: 4),
            combat_pool: { remaining: 2, max: 4 },
            badges: [badge('shock', '2 Shock'), badge('pain', '1 Pain'),
                     badge('major', 'Major: 4')]),

        # Downed Combatant: at 0 HP and cannot act (red row), Major +
        # Poison badges.
        row(4, 102, 'Bryn Ironvein', '6310', can_act: false,
            hp: hp(20, current: 0, major: 20),
            mana: { remaining: 8, max: 8 },
            toxicity: { value: 0, threshold: 7 },
            combat_pool: { remaining: 0, max: 8 },
            badges: [badge('major', 'Major: 20'), badge('poison', 'Poison: 2')]),

        # Freshly spawned: Initiative not yet rolled and vitals not yet
        # wired, so every numeric column falls back to a dash.
        row(5, 305, 'Cult Fanatic', nil)
      ]
    end

    # Build one tracker row, defaulting the optional columns to the
    # "not available" forms (nil vitals render as dashes; no badges).
    def row(combatant_id, creature_id, name, initiative,
            acting: false, can_act: true, hp: nil, mana: nil,
            toxicity: nil, combat_pool: nil, badges: [])
      {
        combatant_id: combatant_id, creature_id: creature_id, name: name,
        initiative: initiative, acting: acting, can_act: can_act,
        hp: hp, mana: mana, toxicity: toxicity, combat_pool: combat_pool,
        badges: badges
      }
    end

    # An HP column value. `current` plus the three damage severities sum
    # to `max`, matching how Conditions partitions a Creature's HP pool.
    def hp(max, current:, minor: 0, moderate: 0, major: 0)
      { current: current, max: max, minor: minor, moderate: moderate, major: major }
    end

    def badge(kind, label)
      { kind: kind, label: label }
    end
  end
end
