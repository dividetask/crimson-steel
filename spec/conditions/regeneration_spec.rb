RSpec.describe 'Regeneration' do
  describe '#regenerate_turn' do
    it 'mends Tier Minor plus 1 Moderate each turn (each Severity on its own counter)' do
      inst = build_instance(state: build_state(hp_damage: { minor: 5, moderate: 3 }))
      result = inst.regenerate_turn(2) # Tier 2 → 2 Minor
      expect(result).to eq(regenerated: true, healed: { minor: 2, moderate: 1 })
      expect(inst.state.hp_damage[:minor]).to eq(3)
      expect(inst.state.hp_damage[:moderate]).to eq(2)
    end

    it 'does not convert Moderate into Minor, and never over-heals past a counter' do
      inst = build_instance(state: build_state(hp_damage: { minor: 1, moderate: 1 }))
      inst.regenerate_turn(3) # heals only the 1 Minor present, plus the 1 Moderate
      expect(inst.state.hp_damage).to be_empty
    end

    it 'a Tier-0 regenerator mends no Minor but still mends 1 Moderate' do
      inst = build_instance(state: build_state(hp_damage: { minor: 2, moderate: 2 }))
      expect(inst.regenerate_turn(0)).to eq(regenerated: true, healed: { minor: 0, moderate: 1 })
      expect(inst.state.hp_damage[:minor]).to eq(2)
      expect(inst.state.hp_damage[:moderate]).to eq(1)
    end

    it 'leaves Major damage to the hourly Regeneration' do
      inst = build_instance(state: build_state(hp_damage: { major: 2 }))
      expect(inst.regenerate_turn(3)).to eq(regenerated: false, healed: { minor: 0, moderate: 0 })
      expect(inst.state.hp_damage[:major]).to eq(2)
    end

    it 'is suppressed while unhealed acid/fire damage remains' do
      inst = build_instance(state: build_state(hp_damage: { minor: 3, moderate: 2 }, elemental_wound: 4))
      expect(inst.regenerate_turn(2)).to eq(regenerated: false, blocked: true)
      expect(inst.state.hp_damage[:minor]).to eq(3)
      expect(inst.state.hp_damage[:moderate]).to eq(2)
    end
  end

  describe '#regenerate_hourly_majors' do
    let(:per_hour) { 600 } # 3600s / 6s-per-round

    it 'seeds the next-due round on first call and heals nothing yet' do
      inst = build_instance(state: build_state(hp_damage: { major: 3 }))
      expect(inst.regenerate_hourly_majors(1000, per_hour)).to eq(healed_major: 0, blocked: false)
      expect(inst.state.regen_major_round).to eq(1600)
      expect(inst.state.hp_damage[:major]).to eq(3)
    end

    it 'mends 1 Major once a whole hour has elapsed' do
      inst = build_instance(state: build_state(hp_damage: { major: 3 }, regen_major_round: 1600))
      expect(inst.regenerate_hourly_majors(1600, per_hour)).to eq(healed_major: 1, blocked: false)
      expect(inst.state.hp_damage[:major]).to eq(2)
      expect(inst.state.regen_major_round).to eq(2200)
    end

    it 'catches up multiple Majors across several elapsed hours' do
      # due at 600, now two hours later → crossings at 600, 1200, 1800 = 3 Majors
      inst = build_instance(state: build_state(hp_damage: { major: 5 }, regen_major_round: 600))
      expect(inst.regenerate_hourly_majors(600 + (2 * per_hour), per_hour)).to include(healed_major: 3)
      expect(inst.state.hp_damage[:major]).to eq(2)
    end

    it 'advances the schedule but heals nothing while suppressed' do
      inst = build_instance(state: build_state(hp_damage: { major: 3 }, regen_major_round: 100, elemental_wound: 2))
      expect(inst.regenerate_hourly_majors(100 + per_hour, per_hour)).to eq(healed_major: 0, blocked: true)
      expect(inst.state.hp_damage[:major]).to eq(3)      # nothing banked
      expect(inst.state.regen_major_round).to eq(100 + (2 * per_hour))
    end
  end

  describe 'elemental (acid/fire) wound gating' do
    it 'accumulates on Apply Elemental Wound and ignores non-positive amounts' do
      inst = build_instance
      expect(inst.apply_elemental_wound(5)).to eq(5)
      expect(inst.apply_elemental_wound(0)).to eq(5)
      expect(inst.apply_elemental_wound(-2)).to eq(5)
      expect(inst.regeneration_blocked?).to be(true)
    end

    it 'is chipped down by natural healing without preventing it, then Regeneration resumes' do
      inst = build_instance(state: build_state(hp_damage: { minor: 3 }, elemental_wound: 2))
      inst.apply_heal(minor: 2) # ordinary healing still works and chips 2 off the wound
      expect(inst.state.elemental_wound).to eq(0)
      expect(inst.regeneration_blocked?).to be(false)
      expect(inst.regenerate_turn(1)).to include(regenerated: true)
    end

    it 'tracks the elemental wound independently of the acid_counter' do
      # The acid_counter is a separate lingering-corrosion pool; only the
      # elemental_wound (actual acid/fire hit-point damage) gates Regeneration.
      inst = build_instance(state: build_state(acid_counter: 5, hp_damage: { minor: 2 }))
      expect(inst.regeneration_blocked?).to be(false)
      expect(inst.regenerate_turn(1)).to include(regenerated: true)
    end
  end

  describe 'State serialization' do
    it 'round-trips the elemental_wound counter and omits it when zero' do
      loaded = Conditions::State.load(Conditions::State.new(elemental_wound: 7).to_h)
      expect(loaded.elemental_wound).to eq(7)
      expect(Conditions::State.new(elemental_wound: 0).to_h).not_to have_key('elemental_wound')
    end

    it 'round-trips the regen_major_round (last-fired) timer and omits it when unset' do
      loaded = Conditions::State.load(Conditions::State.new(regen_major_round: 4200).to_h)
      expect(loaded.regen_major_round).to eq(4200)
      expect(Conditions::State.new.to_h).not_to have_key('regen_major_round')
    end
  end
end
