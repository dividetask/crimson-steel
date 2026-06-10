require 'spec_helper'
require 'proficiencies'

RSpec.describe 'Proficiencies.compute', type: :model do
  # Tiny mock accessor so the tests don't need full Creature
  # Records. Methods match the Creature Accessor's documented surface.
  Mock = Struct.new(:ranks_map, :attrs, :abilities_map, :ability_levels) do
    def ranks_for(key);              ranks_map.fetch(key, 0); end
    def attribute_value(attr);       attrs.fetch(attr.to_sym, 0); end
    def has_ability(name);           abilities_map[name] == true; end
    def level_for_ability(name);     ability_levels.fetch(name, 0); end
  end

  def mock(ranks: {}, attrs: {}, abilities: {}, levels: {})
    Mock.new(ranks, attrs, abilities, levels)
  end

  describe 'Direct Prowess (no Floor, no Substitution)' do
    it 'trained skill: ranks + floor(attr/2)' do
      # Athletics (str). ranks 3, str 4. Prowess = 3 + 2 = 5 → dice 6, bonus 1.
      out = Proficiencies.compute(
        key: 'athletics',
        creature: mock(ranks: { 'athletics' => 3 }, attrs: { str: 4 })
      )
      expect(out).to eq(dice_cap: 6, competency_modifier: ['Competency', 1])
    end

    it 'untrained skill takes the Non-Proficiency Penalty on the TN, not the dice' do
      # ranks 0, dex 3. Dice Prowess = 0 + floor(3/2) = 1 → dice 7, bonus 0.
      # The −2 Non-Proficiency Penalty rides the Competency (TN), not the dice.
      out = Proficiencies.compute(
        key: 'stealth',
        creature: mock(ranks: { 'stealth' => 0 }, attrs: { dex: 3 })
      )
      expect(out).to eq(dice_cap: 7, competency_modifier: ['Competency', -2])
    end

    it 'zero Prowess returns a nil competency_modifier' do
      # ranks 0, attr 0, no penalty? Actually ranks 0 → penalty -2. So zero
      # prowess needs ranks 2 + attr 0 = 2 - penalty=0 (effective_ranks > 0).
      # Use ranks 2, attr 0, no abilities → 2+0+0 = 2. dice 8 bonus 0.
      out = Proficiencies.compute(
        key: 'athletics',
        creature: mock(ranks: { 'athletics' => 2 }, attrs: { str: 0 })
      )
      expect(out[:competency_modifier]).to be_nil
    end
  end

  describe 'Prefix Match (Set Skills)' do
    it 'Set Instance resolves to its family attribute' do
      # perform_dance via perform_ (cha).
      out = Proficiencies.compute(
        key: 'perform_dance',
        creature: mock(ranks: { 'perform_dance' => 4 }, attrs: { cha: 6 })
      )
      # Prowess = 4 + 3 = 7 → dice 8, bonus 1.
      expect(out).to eq(dice_cap: 8, competency_modifier: ['Competency', 1])
    end
  end

  describe 'attribute_override' do
    it 'save key with no catalog entry uses the override attribute' do
      out = Proficiencies.compute(
        key: 'con_save',
        creature: mock(ranks: { 'con_save' => 4 }, attrs: { con: 5 }),
        attribute_override: :con
      )
      # Prowess = 4 + 2 = 6 → dice 7 bonus 1.
      expect(out).to eq(dice_cap: 7, competency_modifier: ['Competency', 1])
    end

    it 'unknown key with no override is invalid' do
      expect {
        Proficiencies.compute(key: 'homebrew_skill', creature: mock)
      }.to raise_error(ArgumentError, /attribute_override/)
    end
  end

  describe 'Floor Ability (jack_of_all_trades)' do
    it 'lifts untrained ranks to floor(level/2)' do
      # history (int). ranks 0, int 2, jack_of_all_trades level 5.
      # Floor = floor(5/2) = 2. Effective ranks 2. Prowess = 2 + 1 + 0 = 3.
      out = Proficiencies.compute(
        key: 'history',
        creature: mock(
          ranks: { 'history' => 0 }, attrs: { int: 2 },
          abilities: { 'jack_of_all_trades' => true },
          levels: { 'jack_of_all_trades' => 5 }
        )
      )
      expect(out).to eq(dice_cap: 9, competency_modifier: nil) # bonus 0
    end

    it 'does not lift below actual ranks' do
      # athletics ranks 6, str 4, floor = floor(8/2) = 4. max(6, 4) = 6. Prowess = 6 + 2 = 8.
      out = Proficiencies.compute(
        key: 'athletics',
        creature: mock(
          ranks: { 'athletics' => 6 }, attrs: { str: 4 },
          abilities: { 'jack_of_all_trades' => true },
          levels: { 'jack_of_all_trades' => 8 }
        )
      )
      # Prowess 8 → dice 9 bonus 1.
      expect(out).to eq(dice_cap: 9, competency_modifier: ['Competency', 1])
    end

    it 'does not apply to Restricted Skills' do
      # restricted_magic is in Restricted Skills config. Floor skipped.
      out = Proficiencies.compute(
        key: 'restricted_magic',
        creature: mock(
          ranks: { 'restricted_magic' => 0 }, attrs: { int: 2 },
          abilities: { 'jack_of_all_trades' => true },
          levels: { 'jack_of_all_trades' => 8 }
        )
      )
      # Floor skipped (Restricted). Dice Prowess = 0 + floor(2/2) = 1 → dice 7;
      # the −2 Non-Proficiency Penalty rides the TN, not the dice.
      expect(out[:dice_cap]).to eq(7)
      expect(out[:competency_modifier]).to eq(['Competency', -2])
    end

    it 'does not apply to keys without a catalog entry' do
      out = Proficiencies.compute(
        key: 'con_save', attribute_override: :con,
        creature: mock(
          ranks: { 'con_save' => 0 }, attrs: { con: 8 },
          abilities: { 'jack_of_all_trades' => true },
          levels: { 'jack_of_all_trades' => 8 }
        )
      )
      # A Save never takes the Non-Proficiency Penalty. Dice Prowess =
      # 0 + floor(8/2) = 4 → dice 10, bonus 0.
      expect(out[:competency_modifier]).to be_nil
      expect(out[:dice_cap]).to eq(10)
    end
  end

  describe 'Substituted Prowess (versatile_performance)' do
    it 'beats Direct when source Prowess is higher' do
      # deception: ranks 0, cha 6, penalty -2 → Direct = 1.
      # perform_act ranks 4 cha 6 → Sub = 4 + 3 = 7. Sub wins.
      out = Proficiencies.compute(
        key: 'deception',
        creature: mock(
          ranks: { 'deception' => 0, 'perform_act' => 4 },
          attrs: { cha: 6 },
          abilities: { 'versatile_performance' => true }
        )
      )
      # Prowess 7 → dice 8 bonus 1.
      expect(out).to eq(dice_cap: 8, competency_modifier: ['Competency', 1])
    end

    it 'loses when Direct Prowess is higher (Direct wins ties)' do
      # acrobatics: ranks 4 dex 4 → Direct = 6.
      # perform_dance ranks 2 cha 0 → Sub = 2 + 0 = 2. Direct wins.
      out = Proficiencies.compute(
        key: 'acrobatics',
        creature: mock(
          ranks: { 'acrobatics' => 4, 'perform_dance' => 2 },
          attrs: { dex: 4, cha: 0 },
          abilities: { 'versatile_performance' => true }
        )
      )
      # Prowess 6 → dice 7 bonus 1.
      expect(out).to eq(dice_cap: 7, competency_modifier: ['Competency', 1])
    end

    it 'skipped when the ability is absent' do
      # No versatile_performance ability → no substituted prowess.
      out = Proficiencies.compute(
        key: 'deception',
        creature: mock(ranks: { 'deception' => 0, 'perform_act' => 8 }, attrs: { cha: 6 })
      )
      # Falls through to direct (untrained Skill): Dice Prowess = 0 + floor(6/2)
      # = 3 → dice 9, bonus 0; the −2 penalty rides the TN.
      expect(out[:competency_modifier]).to eq(['Competency', -2])
      expect(out[:dice_cap]).to eq(9)
    end

    it 'skipped when no Substitution Map entry targets the key' do
      # stealth is not a substitution target.
      out = Proficiencies.compute(
        key: 'stealth',
        creature: mock(
          ranks: { 'stealth' => 0, 'perform_dance' => 8 }, attrs: { dex: 3, cha: 6 },
          abilities: { 'versatile_performance' => true }
        )
      )
      # Direct only (untrained Skill): Dice Prowess = 0 + floor(3/2) = 1 →
      # dice 7; the −2 penalty rides the TN.
      expect(out[:competency_modifier]).to eq(['Competency', -2])
      expect(out[:dice_cap]).to eq(7)
    end
  end

  describe 'Floor + Substitution together' do
    it 'Floor does not lift the substitution source ranks' do
      # deception. Direct: floor lift 5 (jack@10) on deception, ranks 5, cha 6 → 5+3 = 8.
      # Sub from perform_act: ranks 1 (no floor), cha 6 → 1+3 = 4. Direct wins.
      out = Proficiencies.compute(
        key: 'deception',
        creature: mock(
          ranks: { 'deception' => 0, 'perform_act' => 1 }, attrs: { cha: 6 },
          abilities: { 'jack_of_all_trades' => true, 'versatile_performance' => true },
          levels: { 'jack_of_all_trades' => 10 }
        )
      )
      # Direct Prowess 8 → dice 9 bonus 1.
      expect(out).to eq(dice_cap: 9, competency_modifier: ['Competency', 1])
    end
  end

  describe 'untrained_roll_inputs' do
    it 'applies the Floor lift for a Creature with the Floor Ability' do
      # int 2, jack_of_all_trades level 5 → floor 2. Prowess = 2 + 1 + 0 = 3.
      # Matches the trained `history` Floor example (dice 9, bonus 0).
      out = Proficiencies::Compute.untrained_roll_inputs(
        attribute: :int,
        creature: mock(
          attrs: { int: 2 },
          abilities: { 'jack_of_all_trades' => true },
          levels: { 'jack_of_all_trades' => 5 }
        )
      )
      expect(out).to eq(dice_cap: 9, competency_modifier: nil)
    end

    it 'puts the Non-Proficiency Penalty on the TN (not dice) without the Floor Ability' do
      # dex 3, no Floor Ability → Dice Prowess = 0 + floor(3/2) = 1 → dice 7;
      # the −2 penalty rides the Competency.
      out = Proficiencies::Compute.untrained_roll_inputs(
        attribute: :dex,
        creature: mock(attrs: { dex: 3 })
      )
      expect(out).to eq(dice_cap: 7, competency_modifier: ['Competency', -2])
    end
  end
end
