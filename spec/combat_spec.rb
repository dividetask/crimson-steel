require 'tmpdir'
require_relative '../lib/combat'
require_relative '../lib/dice_system'
require_relative '../lib/character'

class ScriptedRandomSource
  def initialize(values)
    @values = values.dup
  end

  def rand_int(_low, _high)
    raise 'random source exhausted' if @values.empty?
    @values.shift
  end
end

# Character + martial-rank override for tests. The real Character
# stub returns 0; the spec needs to drive the action-dice formula
# with arbitrary martial values.
class TestCharacter < Character
  def initialize(martial_skill_ranks: 0, **kwargs)
    super(**kwargs)
    @martial_skill_ranks = martial_skill_ranks
  end

  attr_reader :martial_skill_ranks
end

RSpec.describe Combat do
  dice_config_path = File.expand_path('../data/dice_resolution.yaml', __dir__)

  let(:dice_values) { [] }
  let(:dice_system) { DiceSystem.new(dice_config_path, random_source: ScriptedRandomSource.new(dice_values)) }
  let(:characters) do
    {
      1 => TestCharacter.new(id: 1, name: 'Ash',  player: 'Sam',  race: 'Human',
                             attributes: { wis: 16, dex: 18 }, martial_skill_ranks: 5),
      2 => TestCharacter.new(id: 2, name: 'Bryn', player: 'Mira', race: 'Dwarf',
                             attributes: { wis: 12 }, martial_skill_ranks: 3),
      3 => TestCharacter.new(id: 3, name: 'Lira', player: 'Jordan', race: 'Elf',
                             attributes: { wis: 14 }, martial_skill_ranks: 0)
    }
  end
  let(:lookup) { ->(id) { characters[id] } }

  def make_combat(state_path: nil, rules_path: nil)
    Combat.new(state_path: state_path, rules_path: rules_path,
               dice_system: dice_system, character_lookup: lookup)
  end

  describe 'rules loading' do
    it 'falls back to defaults when no rules file is given' do
      combat = make_combat
      expect(combat.initiative_attribute).to eq(:wis)
      expect(combat.initiative_divisor).to eq(2)
      expect(combat.combat_pool_attribute).to eq(:wis)
      expect(combat.combat_pool_range).to eq(10)
      expect(combat.combat_pool_minimum).to eq(11)
    end

    it 'loads tuned values from the rules YAML' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'combat_rules.yaml')
        File.write(path, { 'Initiative Attribute' => 'dex',
                           'Initiative Divisor' => 3,
                           'Combat Pool Attribute' => 'dex',
                           'Combat Pool Range' => 8,
                           'Combat Pool Minimum' => 5 }.to_yaml)
        combat = make_combat(rules_path: path)
        expect(combat.initiative_attribute).to eq(:dex)
        expect(combat.initiative_divisor).to eq(3)
        expect(combat.combat_pool_attribute).to eq(:dex)
        expect(combat.combat_pool_range).to eq(8)
        expect(combat.combat_pool_minimum).to eq(5)
      end
    end

    it 'uses the configured attribute for initiative and combat pool formulas' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'combat_rules.yaml')
        File.write(path, { 'Initiative Attribute' => 'dex',
                           'Combat Pool Attribute' => 'dex' }.to_yaml)
        combat = make_combat(rules_path: path)
        # Ash dex 18 → 9 initiative dice; raw = 5 + 9 = 14;
        # action_dice_max = 14 % 10 + 11 = 15; bonus = 1.
        expect(combat.initiative_dice_count(1)).to eq(9)
        expect(combat.action_dice_max(1)).to eq(15)
        expect(combat.untyped_bonus(1)).to eq(1)
      end
    end
  end

  describe '#initiative_dice_count' do
    it 'is floor(wisdom / Initiative Divisor)' do
      combat = make_combat
      expect(combat.initiative_dice_count(1)).to eq(8) # 16 / 2
      expect(combat.initiative_dice_count(2)).to eq(6) # 12 / 2
    end

    it 'raises when the character is unknown' do
      combat = make_combat
      expect { combat.initiative_dice_count(99) }.to raise_error(ArgumentError)
    end
  end

  describe '#action_dice_max and #untyped_bonus' do
    it 'matches (raw % range) + minimum, with raw / range as the untyped bonus' do
      combat = make_combat
      # Ash: martial 5 + wis/2 (8) = 13. 13 % 10 = 3. + 11 = 14. Bonus = 1.
      expect(combat.action_dice_max(1)).to eq(14)
      expect(combat.untyped_bonus(1)).to eq(1)
      # Bryn: 3 + 6 = 9. 9 % 10 = 9. + 11 = 20. Bonus = 0.
      expect(combat.action_dice_max(2)).to eq(20)
      expect(combat.untyped_bonus(2)).to eq(0)
      # Lira: 0 + 7 = 7. 7 % 10 = 7. + 11 = 18. Bonus = 0.
      expect(combat.action_dice_max(3)).to eq(18)
      expect(combat.untyped_bonus(3)).to eq(0)
    end

    it 'honors tuned Combat Pool Range / Minimum from the rules file' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'combat_rules.yaml')
        File.write(path, { 'Combat Pool Range' => 5,
                           'Combat Pool Minimum' => 1 }.to_yaml)
        combat = make_combat(rules_path: path)
        # Ash raw = 13. 13 % 5 = 3. + 1 = 4. Bonus = 13 / 5 = 2.
        expect(combat.action_dice_max(1)).to eq(4)
        expect(combat.untyped_bonus(1)).to eq(2)
      end
    end
  end

  describe '#add_combatant / #remove_combatant' do
    it 'assigns sequential per-instance ids and seeds action_dice from the formula' do
      combat = make_combat
      a = combat.add_combatant(char_id: 1, name: 'Ash')
      b = combat.add_combatant(char_id: 1, name: 'Ash#2')
      expect(a['id']).to eq(1)
      expect(b['id']).to eq(2)
      expect(a['char_id']).to eq(1)
      expect(a['action_dice']).to eq(14) # matches action_dice_max(1)
    end

    it 'removes by combat id' do
      combat = make_combat
      a = combat.add_combatant(char_id: 1, name: 'Ash')
      b = combat.add_combatant(char_id: 2, name: 'Bryn')
      expect(combat.remove_combatant(a['id'])).to eq(true)
      expect(combat.combatants.map { |c| c['id'] }).to eq([b['id']])
    end

    it 'returns false when removing an unknown combatant' do
      combat = make_combat
      expect(combat.remove_combatant(999)).to eq(false)
    end
  end

  describe '#reroll_all_initiative' do
    it 'rolls floor(wis/divisor) dice per combatant and stores them sorted desc' do
      dice_values.replace([3, 9, 1, 7, 5, 10, 2, 8, # 8 dice for Ash
                           4, 6, 2, 9, 1, 5])       # 6 dice for Bryn
      combat = make_combat
      ash  = combat.add_combatant(char_id: 1, name: 'Ash')
      bryn = combat.add_combatant(char_id: 2, name: 'Bryn')

      combat.reroll_all_initiative
      expect(ash['initiative_dice']).to eq([10, 9, 8, 7, 5, 3, 2, 1])
      expect(bryn['initiative_dice']).to eq([9, 6, 5, 4, 2, 1])
      expect(combat.active?).to eq(true)
      expect(combat.round).to eq(1)
    end

    it 'positive luck rerolls the lowest non-critical die' do
      dice_values.replace([10, 1, 5, 6, 7, 8, 9, 4, 9])
      combat = make_combat
      ash = combat.add_combatant(char_id: 1, name: 'Ash')
      combat.reroll_all_initiative(luck_by_id: { ash['id'] => 1 })
      expect(ash['initiative_dice']).to eq([10, 9, 9, 8, 7, 6, 5, 4])
    end

    it 'negative luck rerolls the highest non-failure die' do
      dice_values.replace([1, 9, 2, 3, 4, 5, 6, 7, 2])
      combat = make_combat
      ash = combat.add_combatant(char_id: 1, name: 'Ash')
      combat.reroll_all_initiative(luck_by_id: { ash['id'] => -1 })
      expect(ash['initiative_dice']).to eq([7, 6, 5, 4, 3, 2, 2, 1])
    end

    it 'positive insight bumps the lowest die that can become a crit' do
      dice_values.replace([5, 8, 9, 3, 4, 6, 7, 2])
      combat = make_combat
      ash = combat.add_combatant(char_id: 1, name: 'Ash')
      combat.reroll_all_initiative(insight_by_id: { ash['id'] => 2 })
      expect(ash['initiative_dice']).to eq([10, 9, 7, 6, 5, 4, 3, 2])
    end

    it 'positive insight falls back to the highest non-crit when no die can crit' do
      dice_values.replace([2, 3, 4, 5, 6, 7, 10, 1])
      combat = make_combat
      ash = combat.add_combatant(char_id: 1, name: 'Ash')
      combat.reroll_all_initiative(insight_by_id: { ash['id'] => 1 })
      expect(ash['initiative_dice']).to eq([10, 8, 6, 5, 4, 3, 2, 1])
    end

    it 'negative insight penalizes the highest die' do
      dice_values.replace([2, 3, 4, 5, 6, 7, 9, 1])
      combat = make_combat
      ash = combat.add_combatant(char_id: 1, name: 'Ash')
      combat.reroll_all_initiative(insight_by_id: { ash['id'] => -3 })
      expect(ash['initiative_dice']).to eq([7, 6, 6, 5, 4, 3, 2, 1])
    end
  end

  describe '#turn_order' do
    it 'sorts highest initiative first; ties break die-by-die then by id' do
      combat = make_combat
      a = combat.add_combatant(char_id: 1, name: 'A')
      b = combat.add_combatant(char_id: 2, name: 'B')
      c = combat.add_combatant(char_id: 3, name: 'C')
      a['initiative_dice'] = [10, 7]
      b['initiative_dice'] = [10, 8]
      c['initiative_dice'] = [10, 7] # ties A; A wins by lower combat id
      expect(combat.turn_order.map { |x| x['id'] }).to eq([b['id'], a['id'], c['id']])
    end
  end

  describe '#next_turn' do
    it 'advances the pointer and increments the round when it wraps' do
      dice_values.replace([10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 6, 5, 4, 3]) # 8 for A + 6 for B
      combat = make_combat
      combat.add_combatant(char_id: 1, name: 'A')
      combat.add_combatant(char_id: 2, name: 'B')
      combat.reroll_all_initiative
      expect(combat.round).to eq(1)
      first_id = combat.current_combatant['id']

      combat.next_turn
      expect(combat.current_combatant['id']).not_to eq(first_id)
      expect(combat.round).to eq(1)

      combat.next_turn
      expect(combat.current_combatant['id']).to eq(first_id)
      expect(combat.round).to eq(2)
    end
  end

  describe 'action dice' do
    it 'spends and clamps to zero' do
      combat = make_combat
      a = combat.add_combatant(char_id: 1, name: 'A')
      starting = a['action_dice']
      combat.spend_action_dice(a['id'], 3)
      expect(a['action_dice']).to eq(starting - 3)
      combat.spend_action_dice(a['id'], 999)
      expect(a['action_dice']).to eq(0)
    end

    it 'sets a specific value' do
      combat = make_combat
      a = combat.add_combatant(char_id: 1, name: 'A')
      combat.set_action_dice(a['id'], 4)
      expect(a['action_dice']).to eq(4)
    end

    it 'reset_action_dice restores to action_dice_max for one or all combatants' do
      combat = make_combat
      a = combat.add_combatant(char_id: 1, name: 'A')
      b = combat.add_combatant(char_id: 2, name: 'B')
      combat.spend_action_dice(a['id'], 999)
      combat.spend_action_dice(b['id'], 999)
      combat.reset_action_dice
      expect(a['action_dice']).to eq(combat.action_dice_max(1))
      expect(b['action_dice']).to eq(combat.action_dice_max(2))
    end
  end

  describe 'persistence' do
    it 'round-trips state through YAML' do
      Dir.mktmpdir do |dir|
        state_path = File.join(dir, 'combat.yaml')
        rules_path = File.join(dir, 'combat_rules.yaml')
        dice_values.replace([10, 9, 8, 7, 6, 5, 4, 3])
        first = Combat.new(state_path: state_path, rules_path: rules_path,
                           dice_system: dice_system, character_lookup: lookup)
        a = first.add_combatant(char_id: 1, name: 'Ash')
        first.reroll_all_initiative
        first.spend_action_dice(a['id'], 2)

        second = Combat.new(state_path: state_path, rules_path: rules_path,
                            dice_system: DiceSystem.new(dice_config_path),
                            character_lookup: lookup)
        expect(second.active?).to eq(true)
        expect(second.round).to eq(1)
        loaded = second.combatants.first
        expect(loaded['initiative_dice']).to eq([10, 9, 8, 7, 6, 5, 4, 3])
        expect(loaded['action_dice']).to eq(12) # 14 - 2
      end
    end

    it 'derives the next combat id from existing combatants after reload' do
      Dir.mktmpdir do |dir|
        state_path = File.join(dir, 'combat.yaml')
        first = Combat.new(state_path: state_path, rules_path: nil,
                           dice_system: dice_system, character_lookup: lookup)
        first.add_combatant(char_id: 1, name: 'Ash')
        first.add_combatant(char_id: 1, name: 'Ash#2')

        second = Combat.new(state_path: state_path, rules_path: nil,
                            dice_system: dice_system, character_lookup: lookup)
        rec = second.add_combatant(char_id: 2, name: 'Bryn')
        expect(rec['id']).to eq(3)
      end
    end
  end

  # Attack-resolution / Severity Calculation pipeline tests use an
  # extended character that has damage_resilience and a Conditions
  # instance attached so the pipeline can route damage through to
  # APPLY_HIT_POINT_DAMAGE on the target's conditions.
  describe '#apply_attack_damage' do
    require_relative '../lib/conditions'
    require_relative '../lib/damage_types'

    let(:damage_types_path) { File.expand_path('../data/damage_types.yaml', __dir__) }
    let(:conditions_path)   { File.expand_path('../data/conditions.yaml',   __dir__) }
    let(:damage_types) { DamageTypes.new(damage_types_path) }

    # Each character gets a Conditions instance keyed by id.
    let(:conditions_by_char) do
      characters.keys.each_with_object({}) do |id, h|
        h[id] = Conditions.new(
          config_path: conditions_path,
          dice_system: dice_system,
          severities:  damage_types.severities
        )
      end
    end
    let(:conditions_lookup) { ->(char_id) { conditions_by_char[char_id] } }

    # A condition_evaluator that recognizes "target_has_metal_armor"
    # for character 2 only — used to test damage_multiplier.
    let(:condition_evaluator) do
      ->(combat_id, tag) {
        target = combat.combatants.find { |c| c['id'] == combat_id }
        next false unless target
        tag == 'target_has_metal_armor' && target['char_id'] == 2
      }
    end

    let(:combat) do
      Combat.new(
        state_path: nil, rules_path: nil,
        dice_system: dice_system,
        character_lookup: lookup,
        damage_types: damage_types,
        conditions_lookup: conditions_lookup,
        condition_evaluator: condition_evaluator
      )
    end

    before do
      combat.add_combatant(char_id: 1, name: 'Ash')   # combat_id 1
      combat.add_combatant(char_id: 2, name: 'Bryn')  # combat_id 2
    end

    it 'routes fire damage to the moderate severity bucket on Conditions' do
      result = combat.apply_attack_damage(2, 5, damage_type: 'fire')
      expect(result['final_amount']).to eq(5)
      expect(result['severity_split']).to eq({ 'minor' => 0, 'moderate' => 5, 'major' => 0 })
      expect(conditions_by_char[2].hit_point_damage['moderate']).to eq(5)
    end

    it 'applies damage_per_dice when dice_count is supplied (fire +1/2)' do
      # 4 base damage, 6 dice → +3 from damage_per_dice
      result = combat.apply_attack_damage(2, 4, damage_type: 'fire', dice_count: 6)
      expect(result['damage_per_dice_bonus']).to eq(3)
      expect(result['final_amount']).to eq(7)
    end

    it 'applies damage_multiplier when the condition_evaluator returns true' do
      # Electricity vs metal armor → x2 against char 2 (combat_id 2)
      result = combat.apply_attack_damage(2, 5, damage_type: 'electricity')
      expect(result['multiplier']).to eq(2.0)
      expect(result['final_amount']).to eq(10)
    end

    it 'skips damage_multiplier when the evaluator returns false' do
      # combat_id 1 is Ash — no metal armor in the evaluator
      result = combat.apply_attack_damage(1, 5, damage_type: 'electricity')
      expect(result['multiplier']).to eq(1.0)
      expect(result['final_amount']).to eq(5)
    end

    it 'splits Physical damage by Threshold + Damage Resilience' do
      # Stub damage_resilience on the target character.
      class << characters[2]
        def damage_resilience; 2; end
      end
      # threshold 3 + resilience 2 = 5-point buckets
      # 12 damage → 5 minor, 5 moderate, 2 major
      result = combat.apply_attack_damage(2, 12, damage_type: 'physical', threshold: 3)
      expect(result['severity_split']).to eq({ 'minor' => 5, 'moderate' => 5, 'major' => 2 })
    end

    it 'applies the Acid Counter post-damage' do
      result = combat.apply_attack_damage(2, 4, damage_type: 'acid')
      expect(result['side_effects'].first).to include('kind' => 'apply_acid_counter')
      expect(conditions_by_char[2].acid_counter).to eq(4)
    end

    it 'applies Shock from Cold damage at 2 per damage point' do
      result = combat.apply_attack_damage(2, 3, damage_type: 'cold')
      shock_eff = result['side_effects'].find { |s| s['condition_name'] == 'shock' }
      expect(shock_eff['amount']).to eq(6)
      expect(conditions_by_char[2].shock).to eq(6)
    end
  end

  describe '#critical_modifier_for' do
    require_relative '../lib/damage_types'

    let(:damage_types_path) { File.expand_path('../data/damage_types.yaml', __dir__) }
    let(:damage_types) { DamageTypes.new(damage_types_path) }
    let(:combat) do
      Combat.new(
        state_path: nil, rules_path: nil,
        dice_system: dice_system,
        character_lookup: lookup,
        damage_types: damage_types
      )
    end

    it 'returns the damage type override for emotional (3 instead of 2)' do
      expect(combat.critical_modifier_for('emotional')).to eq(3)
    end

    it 'returns the dice resolution default for types without an override' do
      expect(combat.critical_modifier_for('fire')).to eq(DiceSystem::DEFAULT_CRITICAL_MODIFIER)
    end

    it 'returns the default when damage_types is not configured' do
      bare = Combat.new(state_path: nil, rules_path: nil,
                        dice_system: dice_system,
                        character_lookup: lookup)
      expect(bare.critical_modifier_for('emotional')).to eq(DiceSystem::DEFAULT_CRITICAL_MODIFIER)
    end
  end
end
