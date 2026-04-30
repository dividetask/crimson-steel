require_relative '../lib/abilities'
require_relative '../lib/damage_types'

ABILITIES_CONFIG = File.expand_path('../data/abilities_config.yaml', __dir__)
ABILITIES_DATA   = File.expand_path('../data/abilities_data.yaml',   __dir__)
ABILITIES_DAMAGE_TYPES = File.expand_path('../data/damage_types.yaml', __dir__)

RSpec.describe AbilitySystem do
  let(:damage_types) { DamageTypes.new(ABILITIES_DAMAGE_TYPES) }
  let(:abilities) do
    AbilitySystem.new(
      config_path:  ABILITIES_CONFIG,
      data_path:    ABILITIES_DATA,
      damage_types: damage_types
    )
  end

  describe 'loading' do
    it 'lists every entry' do
      expect(abilities.list_entries).to include('Fireball', 'Heal', 'Vicious Mockery')
    end

    it 'filters by type' do
      ability_only = abilities.list_entries(type_filter: 'ability')
      expect(ability_only).to include('Rage', 'Intimidating Shout')
      expect(ability_only).not_to include('Fireball')
    end

    it 'filters by school' do
      pneumancy = abilities.list_entries(school_filter: 'pneumancy')
      expect(pneumancy).to include('Heal')
      expect(pneumancy).not_to include('Fireball')
    end
  end

  describe '#resolve_casting_time' do
    it 'translates aliases' do
      entry = abilities.get_entry('Fireball')
      expect(abilities.resolve_casting_time(entry)).to eq(0.5)
    end

    it 'parses N rounds' do
      entry = abilities.get_entry('Detect Magic')
      expect(abilities.resolve_casting_time(entry)).to eq(2.0)
    end
  end

  describe '#resolve_range' do
    it 'evaluates Range Formulas' do
      entry = abilities.get_entry('Fireball')
      # Medium = 30+10*rank → rank 3 = 60.
      expect(abilities.resolve_range(entry, 3)).to eq(60)
    end

    it 'returns explicit integer ranges verbatim' do
      entry = abilities.get_entry('Sending')
      expect(abilities.resolve_range(entry, 3)).to eq(1000)
    end

    it 'uses Default Reach Feet when reach is omitted' do
      entry = abilities.get_entry('Heal')  # Touch range = reach
      expect(abilities.resolve_range(entry, 3)).to eq(5)
    end
  end

  describe '#resolve_target' do
    it 'returns self for self target' do
      entry = abilities.get_entry('Detect Magic')
      expect(abilities.resolve_target(entry, 3)).to eq('self')
    end

    it 'evaluates a count formula' do
      entry = abilities.get_entry('Dragon Breath')
      expect(abilities.resolve_target(entry, 3)).to eq(4)
    end

    it 'clamps negative results to zero' do
      # Synthesize an entry with a target that goes negative
      entry = abilities.get_entry('Fireball').merge('target' => '0')
      expect(abilities.resolve_target(entry, 3)).to eq(0)
    end
  end

  describe '#resolve_entry' do
    it 'returns the full resolved bag for a single-tier spell' do
      result = abilities.resolve_entry('Fireball', 3)
      expect(result['name']).to eq('Fireball')
      expect(result['type']).to eq('spell')
      expect(result['casting_time_rounds']).to eq(0.5)
      expect(result['range_feet']).to eq(60)
      expect(result['target']).to eq(0)
      expect(result['damage_type']).to eq('fire')
      expect(result['saves'].length).to eq(1)
    end

    it 'resolves multi-tier Variants and substitutes effect_hash names' do
      heal = abilities.resolve_entry('Heal', 3, tier_index: 2)
      expect(heal['name']).to eq('Heal Simple Wounds')
      expect(heal['effect_hash']['minor_damage']).to eq(8)
      expect(heal['description']).to include('8 minor damage')
    end

    it 'applies variant_overrides' do
      vm = abilities.resolve_entry('Vicious Mockery', 3, tier_index: 1)
      expect(vm['name']).to eq('Biting Words')
      expect(vm['attack_roll']).to be true
    end

    it 'classifies named effects' do
      light = abilities.resolve_entry('Blinding Light', 1)
      fail_outcome = light['saves'].first['fail']
      expect(fail_outcome).to eq({ 'kind' => 'effect', 'name' => 'blind' })
    end

    it 'classifies damage effects with the entry damage_type' do
      fb = abilities.resolve_entry('Fireball', 3)
      fail_outcome = fb['saves'].first['fail']
      expect(fail_outcome['kind']).to eq('damage')
      expect(fail_outcome['damage_type']).to eq('fire')
      expect(fail_outcome['formula']).to eq('8*rank')
    end

    it 'preserves explicit per-Effect severity from the string' do
      synthetic = AbilitySystem.allocate
      synthetic.send(:initialize, config_path: ABILITIES_CONFIG, data_path: ABILITIES_DATA, damage_types: damage_types)
      classified = synthetic.send(
        :classify_effect,
        '4*rank major damage',
        { 'rank' => 3, 'tier' => 2 },
        nil
      )
      expect(classified['severity']).to eq('major')
      expect(classified['formula']).to eq('4*rank')
    end
  end

  describe '#evaluate_damage' do
    it 'applies success and critical to the formula and floors' do
      sr = abilities.resolve_entry('Scorching Ray', 2)
      effect = sr['saves'].first['fail']
      result = abilities.evaluate_damage(effect, 2, 1)
      # 4*rank + 2*success + 3*critical with rank=2, success=2, crit=1
      # = 8 + 4 + 3 = 15
      expect(result).to eq(15)
    end

    it 'clamps negative results to zero' do
      effect = {
        'kind'       => 'damage',
        'formula'    => '0 - 5',
        'context'    => { 'rank' => 1, 'tier' => 1 },
        'damage_type' => 'fire',
        'severity'   => nil
      }
      expect(abilities.evaluate_damage(effect, 0, 0)).to eq(0)
    end
  end

  describe 'aspect-axis Variants' do
    it 'resolves the Elemental Dart entry per aspect' do
      fire_dart = abilities.resolve_entry('Elemental Dart', 1, aspect_index: 0)
      expect(fire_dart['name']).to eq('Fire Dart')
      expect(fire_dart['damage_type']).to eq('fire')
      expect(fire_dart['description']).to include('fire')

      acid_dart = abilities.resolve_entry('Elemental Dart', 1, aspect_index: 1)
      expect(acid_dart['name']).to eq('Acid Dart')
      expect(acid_dart['damage_type']).to eq('acid')
    end
  end
end
