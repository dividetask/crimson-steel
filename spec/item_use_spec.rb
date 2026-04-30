require_relative '../lib/item_use'
require_relative '../lib/equipment'
require_relative '../lib/abilities'
require_relative '../lib/conditions'
require_relative '../lib/dice_system'
require_relative '../lib/damage_types'

ITEM_USE_EQUIPMENT_PATH = File.expand_path('../data/equipment_config.yaml', __dir__)
ITEM_USE_ABILITIES_CONFIG = File.expand_path('../data/abilities_config.yaml', __dir__)
ITEM_USE_ABILITIES_DATA   = File.expand_path('../data/abilities_data.yaml',   __dir__)
ITEM_USE_CONDITIONS_PATH  = File.expand_path('../data/conditions.yaml',       __dir__)
ITEM_USE_DICE_PATH        = File.expand_path('../data/dice_resolution.yaml',  __dir__)
ITEM_USE_DAMAGE_TYPES_PATH = File.expand_path('../data/damage_types.yaml',    __dir__)

RSpec.describe ItemUse do
  let(:dice_system)  { DiceSystem.new(ITEM_USE_DICE_PATH) }
  let(:damage_types) { DamageTypes.new(ITEM_USE_DAMAGE_TYPES_PATH) }
  let(:equipment)    { Equipment.new(config_path: ITEM_USE_EQUIPMENT_PATH) }
  let(:abilities) do
    AbilitySystem.new(
      config_path:  ITEM_USE_ABILITIES_CONFIG,
      data_path:    ITEM_USE_ABILITIES_DATA,
      damage_types: damage_types
    )
  end
  let(:target_conditions) do
    Conditions.new(
      config_path: ITEM_USE_CONDITIONS_PATH,
      dice_system: dice_system,
      severities:  damage_types.severities
    )
  end
  let(:conditions_lookup) { ->(_char_id) { target_conditions } }
  let(:item_use) do
    ItemUse.new(
      equipment:         equipment,
      abilities:         abilities,
      conditions_lookup: conditions_lookup
    )
  end

  describe 'consuming a Heal potion' do
    before do
      # Tier 2 Heal potion (axis_index 2 → tier value 2,
      # minor_damage = 8, moderate_damage = 4, major_damage = 0).
      equipment.add_item('character:1', {
        'item_type' => 'Heal',
        'quantity'  => 1,
        'tier'      => 2
      })
    end

    it 'heals minor and moderate damage on the target via the cure cascade' do
      target_conditions.apply_hit_point_damage('minor' => 5, 'moderate' => 3)
      result = item_use.consume(
        owner_id:       'character:1',
        stack_index:    0,
        item_form:      ItemUse::POTION_FORM,
        spell_name:     'Heal',
        target_char_id: 1,
        rank:           2,
        user_tier:      2,
        target_tier:    2
      )
      heal = result['applications'].find { |a| a['kind'] == 'heal' }
      expect(heal['pools']).to eq({ 'minor' => 8, 'moderate' => 4, 'major' => 0 })
      expect(target_conditions.hit_point_damage['minor']).to eq(0)
      expect(target_conditions.hit_point_damage['moderate']).to eq(0)
    end

    it 'imposes magic toxicity on the target with the potion overhead' do
      result = item_use.consume(
        owner_id:       'character:1',
        stack_index:    0,
        item_form:      ItemUse::POTION_FORM,
        spell_name:     'Heal',
        target_char_id: 1,
        rank:           2,
        user_tier:      2,
        target_tier:    2
      )
      tox_app = result['applications'].find { |a| a['kind'] == 'magic_toxicity' }
      # saturation = tier*5 = 10. base = max(10 - 2, 4) = 8.
      # potion overhead = floor(2 * 2 * 2^0) = 4. total = 12.
      expect(tox_app['amount']).to eq(12)
      expect(target_conditions.magic_toxicity).to eq(12)
    end

    it 'decrements the item quantity to zero and cleans up the stack' do
      item_use.consume(
        owner_id:       'character:1',
        stack_index:    0,
        item_form:      ItemUse::POTION_FORM,
        spell_name:     'Heal',
        target_char_id: 1,
        rank:           2,
        user_tier:      2,
        target_tier:    2
      )
      expect(equipment.get_inventory('character:1')).to be_empty
    end

    it 'refuses to land cure when the target is at the saturation cap' do
      target_conditions.apply_magic_toxicity(20)
      result = item_use.consume(
        owner_id:       'character:1',
        stack_index:    0,
        item_form:      ItemUse::POTION_FORM,
        spell_name:     'Heal',
        target_char_id: 1,
        rank:           2,
        user_tier:      2,
        target_tier:    2,
        target_max_toxicity: 20
      )
      expect(result['saturation_blocked']).to be true
      expect(result['applications']).to be_empty
      expect(result['quantity_decrement']).to eq(0)
      expect(equipment.get_inventory('character:1').first['quantity']).to eq(1)
    end
  end

  describe 'consuming a Heal scroll with improved_healing' do
    before do
      equipment.add_item('character:1', {
        'item_type' => 'Heal',
        'quantity'  => 1,
        'tier'      => 2
      })
    end

    it 'reduces saturation by 2 * user_tier and applies no potion overhead' do
      result = item_use.consume(
        owner_id:       'character:1',
        stack_index:    0,
        item_form:      ItemUse::SCROLL_FORM,
        spell_name:     'Heal',
        target_char_id: 1,
        rank:           2,
        user_tier:      3,
        target_tier:    2,
        user_abilities: ['improved_healing']
      )
      tox_app = result['applications'].find { |a| a['kind'] == 'magic_toxicity' }
      # saturation = 10. tier_reduction = target_tier(2) + 2*user_tier(3) = 8.
      # base = max(10 - 8, minimum=4) = 4. no overhead → 4.
      expect(tox_app['amount']).to eq(4)
    end
  end

  describe 'consuming a Ward potion' do
    before do
      equipment.add_item('character:1', {
        'item_type' => 'Ward',
        'quantity'  => 1,
        'tier'      => 2
      })
    end

    it 'grants Temporary HP and bypasses the saturation cap' do
      target_conditions.apply_magic_toxicity(20)
      result = item_use.consume(
        owner_id:       'character:1',
        stack_index:    0,
        item_form:      ItemUse::POTION_FORM,
        spell_name:     'Ward',
        target_char_id: 1,
        rank:           2,
        user_tier:      2,
        target_tier:    2,
        target_max_toxicity: 20
      )
      ward_app = result['applications'].find { |a| a['kind'] == 'ward' }
      expect(ward_app['amount']).to eq(8)
      expect(target_conditions.temporary_hit_points['amount']).to eq(8)
      expect(result['saturation_blocked']).to be false
    end
  end

  describe 'consuming a Recharge mana scroll' do
    before do
      equipment.add_item('character:1', {
        'item_type' => 'Recharge',
        'quantity'  => 1,
        'tier'      => 2
      })
    end

    it 'surfaces the mana amount as unrouted (caller applies to mana store)' do
      result = item_use.consume(
        owner_id:       'character:1',
        stack_index:    0,
        item_form:      ItemUse::SCROLL_FORM,
        spell_name:     'Recharge',
        target_char_id: 1,
        rank:           2,
        user_tier:      2,
        target_tier:    2
      )
      mana_app = result['applications'].find { |a| a['kind'] == 'mana' }
      expect(mana_app['amount']).to eq(8)
      expect(mana_app['unrouted']).to be true
    end
  end
end
