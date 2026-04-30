require_relative '../lib/casting'
require_relative '../lib/abilities'
require_relative '../lib/conditions'
require_relative '../lib/dice_system'
require_relative '../lib/damage_types'

CASTING_ABILITIES_CONFIG = File.expand_path('../data/abilities_config.yaml', __dir__)
CASTING_ABILITIES_DATA   = File.expand_path('../data/abilities_data.yaml',   __dir__)
CASTING_CONDITIONS_PATH  = File.expand_path('../data/conditions.yaml',       __dir__)
CASTING_DICE_PATH        = File.expand_path('../data/dice_resolution.yaml',  __dir__)
CASTING_DAMAGE_TYPES_PATH = File.expand_path('../data/damage_types.yaml',    __dir__)

RSpec.describe Casting do
  let(:dice_system)  { DiceSystem.new(CASTING_DICE_PATH) }
  let(:damage_types) { DamageTypes.new(CASTING_DAMAGE_TYPES_PATH) }
  let(:abilities) do
    AbilitySystem.new(
      config_path:  CASTING_ABILITIES_CONFIG,
      data_path:    CASTING_ABILITIES_DATA,
      damage_types: damage_types
    )
  end

  let(:caster_conditions) do
    Conditions.new(
      config_path: CASTING_CONDITIONS_PATH,
      dice_system: dice_system,
      severities:  damage_types.severities
    )
  end
  let(:target_conditions) do
    Conditions.new(
      config_path: CASTING_CONDITIONS_PATH,
      dice_system: dice_system,
      severities:  damage_types.severities
    )
  end
  let(:conditions_by_id) { { 1 => caster_conditions, 2 => target_conditions } }
  let(:conditions_lookup) { ->(char_id) { conditions_by_id[char_id] } }
  let(:casting) { Casting.new(abilities: abilities, conditions_lookup: conditions_lookup) }

  describe 'casting Heal' do
    before do
      caster_conditions.set_mana(20, max: 20)
      target_conditions.apply_hit_point_damage('minor' => 5, 'moderate' => 3)
    end

    it 'applies the cure cascade to the target' do
      result = casting.cast(
        spell_name:     'Heal',
        caster_char_id: 1,
        target_char_id: 2,
        rank:           2,
        mana_cost:      4,
        tier_index:     2
      )
      heal = result['applications'].find { |a| a['kind'] == 'heal' }
      expect(heal['pools']).to eq({ 'minor' => 8, 'moderate' => 4, 'major' => 0 })
      expect(target_conditions.hit_point_damage['minor']).to eq(0)
      expect(target_conditions.hit_point_damage['moderate']).to eq(0)
    end

    it 'spends mana from the caster' do
      result = casting.cast(
        spell_name:     'Heal',
        caster_char_id: 1,
        target_char_id: 2,
        rank:           2,
        mana_cost:      6,
        tier_index:     2
      )
      expect(result['mana_spent']).to eq(6)
      expect(caster_conditions.current_mana).to eq(14)
    end

    it 'imposes Magic Toxicity on the caster, not the target' do
      result = casting.cast(
        spell_name:     'Heal',
        caster_char_id: 1,
        target_char_id: 2,
        rank:           2,
        mana_cost:      0,
        tier_index:     2
      )
      tox_app = result['applications'].find { |a| a['kind'] == 'magic_toxicity_caster' }
      # Heal at tier 2: saturation = tier*5 = 10. minimum = tier*2 = 4. max = 10.
      expect(tox_app['amount']).to eq(10)
      expect(caster_conditions.magic_toxicity).to eq(10)
      expect(target_conditions.magic_toxicity).to eq(0)
    end
  end

  describe 'mana enforcement' do
    it 'returns insufficient_mana without spending or applying effects' do
      caster_conditions.set_mana(2, max: 20)
      target_conditions.apply_hit_point_damage('minor' => 3)
      result = casting.cast(
        spell_name:     'Heal',
        caster_char_id: 1,
        target_char_id: 2,
        rank:           2,
        mana_cost:      5,
        tier_index:     2
      )
      expect(result['error']).to eq('insufficient_mana')
      expect(caster_conditions.current_mana).to eq(2)
      expect(target_conditions.hit_point_damage['minor']).to eq(3)
    end
  end

  describe 'saturation gate (caster-side)' do
    it 'blocks cure spells when the caster is at or above the cap' do
      caster_conditions.set_mana(20, max: 20)
      caster_conditions.apply_magic_toxicity(20)
      target_conditions.apply_hit_point_damage('minor' => 5)
      result = casting.cast(
        spell_name:          'Heal',
        caster_char_id:      1,
        target_char_id:      2,
        rank:                2,
        mana_cost:           4,
        tier_index:          2,
        caster_max_toxicity: 20
      )
      expect(result['saturation_blocked']).to be true
      expect(result['mana_spent']).to eq(0)
      expect(result['applications']).to eq([])
      expect(caster_conditions.current_mana).to eq(20)
      expect(target_conditions.hit_point_damage['minor']).to eq(5)
    end

    it 'lets ward spells land regardless of caster saturation' do
      caster_conditions.set_mana(20, max: 20)
      caster_conditions.apply_magic_toxicity(20)
      result = casting.cast(
        spell_name:          'Ward',
        caster_char_id:      1,
        target_char_id:      2,
        rank:                2,
        mana_cost:           2,
        tier_index:          2,
        caster_max_toxicity: 20
      )
      ward = result['applications'].find { |a| a['kind'] == 'ward' }
      expect(ward['amount']).to eq(8)
      expect(target_conditions.temporary_hit_points['amount']).to eq(8)
    end
  end

  describe 'casting Recharge with target_max_mana' do
    it 'restores mana on the target' do
      caster_conditions.set_mana(20, max: 20)
      target_conditions.set_mana(2, max: 100)
      result = casting.cast(
        spell_name:      'Recharge',
        caster_char_id:  1,
        target_char_id:  2,
        rank:            2,
        mana_cost:       3,
        tier_index:      2,
        target_max_mana: 100
      )
      mana_app = result['applications'].find { |a| a['kind'] == 'mana' }
      expect(mana_app['amount']).to eq(8)
      expect(mana_app['gained']).to eq(8)
      expect(target_conditions.current_mana).to eq(10)
    end
  end

  describe 'damage spells return deferred effects' do
    it 'returns saves intact for caller-driven save resolution' do
      caster_conditions.set_mana(20, max: 20)
      result = casting.cast(
        spell_name:     'Fireball',
        caster_char_id: 1,
        target_char_id: 2,
        rank:           3,
        mana_cost:      5
      )
      expect(result['save_specs']).not_to be_empty
      first_save = result['save_specs'].first
      expect(first_save['attribute']).to eq('dex')
      expect(first_save['fail']['kind']).to eq('damage')
      expect(first_save['fail']['damage_type']).to eq('fire')
    end
  end

  describe 'concentration block' do
    it 'returns the resolved concentration block when the spell has one' do
      caster_conditions.set_mana(20, max: 20)
      result = casting.cast(
        spell_name:     'Heal',
        caster_char_id: 1,
        target_char_id: 2,
        rank:           2,
        mana_cost:      0,
        tier_index:     2
      )
      expect(result['concentration']).not_to be_nil
      expect(result['concentration']['action']).to eq('Main Action')
    end

    it 'returns nil when the spell has no concentration' do
      caster_conditions.set_mana(20, max: 20)
      result = casting.cast(
        spell_name:     'Fireball',
        caster_char_id: 1,
        target_char_id: 2,
        rank:           3,
        mana_cost:      0
      )
      expect(result['concentration']).to be_nil
    end
  end
end
