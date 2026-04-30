require_relative '../lib/conditions'
require_relative '../lib/dice_system'
require_relative '../lib/damage_types'

CONDITIONS_PATH = File.expand_path('../data/conditions.yaml', __dir__)
DICE_PATH       = File.expand_path('../data/dice_resolution.yaml', __dir__)
DAMAGE_TYPES_PATH = File.expand_path('../data/damage_types.yaml', __dir__)

class ScriptedRandom
  def initialize(values)
    @values = values.dup
  end

  def rand_int(_low, _high)
    @values.shift
  end
end

RSpec.describe Conditions do
  let(:dice_system)   { DiceSystem.new(DICE_PATH) }
  let(:damage_types)  { DamageTypes.new(DAMAGE_TYPES_PATH) }
  let(:conditions) do
    Conditions.new(
      config_path: CONDITIONS_PATH,
      dice_system: dice_system,
      severities:  damage_types.severities
    )
  end

  describe 'initial state' do
    it 'starts with all counters at zero' do
      expect(conditions.hit_point_damage).to eq({ 'minor' => 0, 'moderate' => 0, 'major' => 0 })
      expect(conditions.ability_damage).to eq({})
      expect(conditions.temporary_hit_points).to be_nil
      expect(conditions.magic_toxicity).to eq(0)
      expect(conditions.shock).to eq(0)
      expect(conditions.acid_counter).to eq(0)
      expect(conditions.afflictions).to eq({})
      expect(conditions.effects).to eq([])
    end
  end

  describe '#apply_hit_point_damage' do
    it 'lands damage at the named severities when no temp HP' do
      result = conditions.apply_hit_point_damage('minor' => 3, 'moderate' => 2, 'major' => 1)
      expect(conditions.hit_point_damage).to eq({ 'minor' => 3, 'moderate' => 2, 'major' => 1 })
      expect(result['absorbed']).to eq({ 'minor' => 0, 'moderate' => 0, 'major' => 0 })
      expect(result['dealt']).to eq({ 'minor' => 3, 'moderate' => 2, 'major' => 1 })
    end

    it 'absorbs worst-first into Temporary HP' do
      conditions.set_temporary_hit_points(3, 'src')
      result = conditions.apply_hit_point_damage('major' => 1, 'moderate' => 5)
      expect(result['absorbed']).to eq({ 'minor' => 0, 'moderate' => 2, 'major' => 1 })
      expect(result['dealt']).to eq({ 'minor' => 0, 'moderate' => 3, 'major' => 0 })
      expect(conditions.temporary_hit_points).to be_nil
    end

    it 'rejects unknown severity keys' do
      expect { conditions.apply_hit_point_damage('catastrophic' => 1) }.to raise_error(ArgumentError)
    end
  end

  describe '#apply_hit_point_heal_cascade' do
    it 'heals worst-first and cascades excess down' do
      conditions.apply_hit_point_damage('major' => 2, 'moderate' => 4, 'minor' => 6)
      healed = conditions.apply_hit_point_heal_cascade('major' => 5, 'moderate' => 0, 'minor' => 0)
      expect(healed).to eq({ 'major' => 2, 'moderate' => 3, 'minor' => 0 })
      expect(conditions.hit_point_damage).to eq({ 'major' => 0, 'moderate' => 1, 'minor' => 6 })
    end
  end

  describe '#set_temporary_hit_points' do
    it 'accepts a strictly higher amount' do
      conditions.set_temporary_hit_points(5, 'a')
      result = conditions.set_temporary_hit_points(8, 'b')
      expect(result['accepted']).to be true
      expect(result['replaced_source_id']).to eq('a')
      expect(conditions.temporary_hit_points['amount']).to eq(8)
    end

    it 'rejects equal or lower' do
      conditions.set_temporary_hit_points(5, 'a')
      result = conditions.set_temporary_hit_points(5, 'b')
      expect(result['accepted']).to be false
      expect(conditions.temporary_hit_points['source_id']).to eq('a')
    end

    it 'clears on a non-positive amount' do
      conditions.set_temporary_hit_points(5, 'a')
      conditions.set_temporary_hit_points(0, 'b')
      expect(conditions.temporary_hit_points).to be_nil
    end
  end

  describe '#apply_ability_damage and #apply_ability_heal_cascade' do
    it 'heals FIFO across attributes within a category' do
      conditions.apply_ability_damage('con', 'minor', 3)
      conditions.apply_ability_damage('str', 'minor', 4)
      healed = conditions.apply_ability_heal_cascade('minor' => 5)
      expect(healed['minor']).to eq(5)
      # con is fully healed — pruned from the dict
      expect(conditions.ability_damage).not_to have_key('con')
      expect(conditions.ability_damage['str']['minor']).to eq(2)
    end

    it 'cascades worst-first like HP healing' do
      conditions.apply_ability_damage('str', 'major', 2)
      conditions.apply_ability_damage('str', 'moderate', 3)
      healed = conditions.apply_ability_heal_cascade('major' => 5)
      expect(healed).to eq({ 'major' => 2, 'moderate' => 3, 'minor' => 0 })
    end
  end

  describe '#apply_shock and #consume_shock' do
    it 'persists overflow shock across consumes' do
      conditions.apply_shock(15)
      expect(conditions.consume_shock(10)).to eq(10)
      expect(conditions.shock).to eq(5)
      expect(conditions.consume_shock(10)).to eq(5)
      expect(conditions.shock).to eq(0)
    end
  end

  describe '#apply_acid_damage and #resolve_acid_turn_start' do
    it 'halves the counter (floored) and deals minor damage at the new value' do
      conditions.apply_acid_damage(7)
      result = conditions.resolve_acid_turn_start
      expect(conditions.acid_counter).to eq(3)
      expect(result['counter_after']).to eq(3)
      expect(conditions.hit_point_damage['minor']).to eq(3)
    end

    it 'removes the counter once it halves to zero' do
      conditions.apply_acid_damage(1)
      result = conditions.resolve_acid_turn_start
      expect(conditions.acid_counter).to eq(0)
      expect(result['damage_dealt']).to be_nil
    end
  end

  describe '#apply_effect and #get_modifiers' do
    it 'replaces an effect with the same source_id in place' do
      conditions.apply_effect(target_key: 'str', bonus_type: 'Inherent', sign: 'bonus', amount: 2, source_id: 'belt')
      conditions.apply_effect(target_key: 'str', bonus_type: 'Inherent', sign: 'bonus', amount: 4, source_id: 'belt')
      expect(conditions.effects.length).to eq(1)
      expect(conditions.effects.first['amount']).to eq(4)
    end

    it 'returns the highest bonus and highest penalty per type' do
      conditions.apply_effect(target_key: 'str', bonus_type: 'Inherent', sign: 'bonus',   amount: 2, source_id: 'a')
      conditions.apply_effect(target_key: 'str', bonus_type: 'Inherent', sign: 'bonus',   amount: 4, source_id: 'b')
      conditions.apply_effect(target_key: 'str', bonus_type: 'Inherent', sign: 'penalty', amount: 1, source_id: 'c')
      mods = conditions.get_modifiers('str')
      expect(mods).to eq({ 'Inherent Bonus' => 4, 'Inherent Penalty' => 1 })
    end

    it 'skips amount-zero effects in lookup' do
      conditions.apply_effect(target_key: 'dex', bonus_type: 'Inherent', sign: 'bonus', amount: 0, source_id: 'x')
      expect(conditions.get_modifiers('dex')).to eq({})
    end
  end

  describe '#remove_effects_by_prefix' do
    it 'removes only the entries whose source_id starts with the prefix' do
      conditions.apply_effect(target_key: 'str', bonus_type: 'Inherent', sign: 'bonus', amount: 2, source_id: 'equipment:char_42:belt')
      conditions.apply_effect(target_key: 'cha', bonus_type: 'Inherent', sign: 'bonus', amount: 1, source_id: 'equipment:char_42:cloak')
      conditions.apply_effect(target_key: 'wis', bonus_type: 'Morale',   sign: 'bonus', amount: 1, source_id: 'spell:bless')
      removed = conditions.remove_effects_by_prefix('equipment:char_42:')
      expect(removed.length).to eq(2)
      expect(conditions.effects.length).to eq(1)
      expect(conditions.effects.first['source_id']).to eq('spell:bless')
    end
  end

  describe '#clear_expired_effects' do
    it 'removes effects whose ends_on_round has passed' do
      conditions.apply_effect(target_key: 'str', bonus_type: 'Inherent', sign: 'bonus', amount: 2, ends_on_round: 5,  source_id: 'a')
      conditions.apply_effect(target_key: 'str', bonus_type: 'Inherent', sign: 'bonus', amount: 1, ends_on_round: 10, source_id: 'b')
      result = conditions.clear_expired_effects(5)
      expect(result['removed_effects'].length).to eq(1)
      expect(conditions.effects.length).to eq(1)
      expect(conditions.effects.first['source_id']).to eq('b')
    end

    it 'clears Temporary HP when its ends_on_round has passed' do
      conditions.set_temporary_hit_points(3, 'src', 5)
      result = conditions.clear_expired_effects(6)
      expect(result['temporary_hit_points_cleared']).to be true
      expect(conditions.temporary_hit_points).to be_nil
    end
  end

  describe '#apply_named_effect' do
    it 'applies modifier-kind mechanics from the catalog' do
      result = conditions.apply_named_effect('paralyzed', 5, 'spell:hold_person')
      expect(result['name']).to eq('paralyzed')
      expect(conditions.effects).not_to be_empty
      attack_against = conditions.effects.find { |e| e['target_key'] == 'attacks_against' }
      expect(attack_against['sign']).to eq('bonus')
      expect(attack_against['amount']).to eq(2)
    end

    it 'raises on unknown name' do
      expect { conditions.apply_named_effect('not_real', 5, 'spell:fake') }.to raise_error(ArgumentError, /Unknown named effect/)
    end
  end

  describe '#inflict_affliction' do
    it 'creates a new affliction with severity and inflicting_tier' do
      result = conditions.inflict_affliction('bleeding', 4, 2)
      expect(result['newly_added']).to be true
      expect(result['severity']).to eq(4)
      expect(result['inflicting_tier']).to eq(2)
    end

    it 'accumulates severity and raises inflicting_tier on re-inflict' do
      conditions.inflict_affliction('bleeding', 3, 1)
      result = conditions.inflict_affliction('bleeding', 2, 3)
      expect(result['newly_added']).to be false
      expect(result['severity']).to eq(5)
      expect(result['inflicting_tier']).to eq(3)
    end

    it 'rejects unknown affliction names' do
      expect { conditions.inflict_affliction('not_real', 1, 0) }.to raise_error(ArgumentError, /Unknown affliction/)
    end
  end

  describe '#resolve_affliction' do
    it 'reduces severity by successes and removes when severity hits zero' do
      conditions.inflict_affliction('bleeding', 1, 1)
      # Bleeding overrides severity_per_success to "tier" → tier 2 = 2 per success.
      # severity_decay defaults to "tier" → 2.
      # Use a scripted dice source to force a save outcome.
      die_size = dice_system.dice_resolution_config['Die Size']
      scripted = DiceSystem.new(DICE_PATH, random_source: ScriptedRandom.new([die_size, die_size]))
      cond = Conditions.new(
        config_path: CONDITIONS_PATH,
        dice_system: scripted,
        severities:  damage_types.severities
      )
      cond.inflict_affliction('bleeding', 1, 1)
      result = cond.resolve_affliction('bleeding', { 'dice_count' => 2, 'modifiers' => {} }, 2)
      expect(result['successes']).to be > 0
      expect(result['removed']).to be true
    end
  end

  describe 'serialization' do
    it 'round-trips through to_dict / load_state' do
      conditions.apply_hit_point_damage('minor' => 3, 'moderate' => 1)
      conditions.set_temporary_hit_points(4, 'src')
      conditions.apply_shock(2)
      conditions.apply_acid_damage(5)
      conditions.apply_effect(target_key: 'str', bonus_type: 'Inherent', sign: 'bonus', amount: 2, source_id: 'belt')
      conditions.inflict_affliction('bleeding', 3, 1)

      snapshot = conditions.to_dict
      reloaded = Conditions.new(
        config_path: CONDITIONS_PATH,
        dice_system: dice_system,
        severities:  damage_types.severities,
        initial_state: snapshot
      )
      expect(reloaded.to_dict).to eq(snapshot)
    end
  end
end
