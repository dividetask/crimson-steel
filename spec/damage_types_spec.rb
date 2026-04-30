require_relative '../lib/damage_types'
require 'tempfile'

DAMAGE_TYPES_CONFIG_PATH = File.expand_path('../data/damage_types.yaml', __dir__)

RSpec.describe DamageTypes do
  let(:damage_types) { DamageTypes.new(DAMAGE_TYPES_CONFIG_PATH) }

  describe 'loading the canonical config' do
    it 'exposes the three severities in least-to-most order' do
      expect(damage_types.severities).to eq(%w[minor moderate major])
    end

    it 'lists every declared type' do
      expect(damage_types.names).to include(
        'physical', 'fire', 'acid', 'electricity',
        'cold', 'emotional', 'necrotic', 'radiant'
      )
    end

    it 'reports physical as runtime-bucketed' do
      expect(damage_types.runtime_bucketing?('physical')).to be true
      expect(damage_types.severity_for('physical')).to be_nil
    end

    it 'returns severity for non-physical types' do
      expect(damage_types.severity_for('fire')).to eq('moderate')
      expect(damage_types.severity_for('cold')).to eq('minor')
      expect(damage_types.severity_for('necrotic')).to eq('major')
    end

    it 'returns the mechanic list verbatim' do
      fire = damage_types.mechanics_for('fire')
      expect(fire).to eq([{ 'kind' => 'damage_per_dice', 'bonus' => 1, 'per' => 2 }])
    end

    it 'returns descriptions' do
      expect(damage_types.description_for('necrotic')).to include('withers life force')
    end
  end

  describe '#known?' do
    it 'reports declared types as known' do
      expect(damage_types.known?('fire')).to be true
    end

    it 'reports unknown names as not known' do
      expect(damage_types.known?('not_a_type')).to be false
    end
  end

  describe '#definition' do
    it 'raises for unknown names' do
      expect { damage_types.definition('not_a_type') }.to raise_error(ArgumentError, /Unknown damage type/)
    end
  end

  describe 'validation' do
    def with_config(yaml_text)
      f = Tempfile.new(['damage_types', '.yaml'])
      f.write(yaml_text)
      f.flush
      yield f.path
    ensure
      f&.close!
    end

    it 'rejects a type that declares both severity and runtime_bucketing' do
      yaml = <<~YAML
        Severities: [minor, moderate, major]
        Damage Types:
          weird:
            severity: moderate
            runtime_bucketing: true
            mechanics: []
      YAML
      with_config(yaml) do |path|
        expect { DamageTypes.new(path) }.to raise_error(ArgumentError, /cannot declare both/)
      end
    end

    it 'rejects a type that declares neither' do
      yaml = <<~YAML
        Severities: [minor, moderate, major]
        Damage Types:
          empty:
            mechanics: []
      YAML
      with_config(yaml) do |path|
        expect { DamageTypes.new(path) }.to raise_error(ArgumentError, /must declare either/)
      end
    end

    it 'rejects an unknown severity' do
      yaml = <<~YAML
        Severities: [minor, moderate, major]
        Damage Types:
          weird:
            severity: catastrophic
            mechanics: []
      YAML
      with_config(yaml) do |path|
        expect { DamageTypes.new(path) }.to raise_error(ArgumentError, /not in/)
      end
    end

    it 'rejects an unknown mechanic kind' do
      yaml = <<~YAML
        Severities: [minor, moderate, major]
        Damage Types:
          weird:
            severity: moderate
            mechanics:
              - kind: nope
      YAML
      with_config(yaml) do |path|
        expect { DamageTypes.new(path) }.to raise_error(ArgumentError, /unrecognized kind/)
      end
    end

    it 'rejects a mechanic missing required fields' do
      yaml = <<~YAML
        Severities: [minor, moderate, major]
        Damage Types:
          weird:
            severity: moderate
            mechanics:
              - kind: damage_per_dice
                bonus: 1
      YAML
      with_config(yaml) do |path|
        expect { DamageTypes.new(path) }.to raise_error(ArgumentError, /missing fields/)
      end
    end

    it 'accepts apply_acid_counter without per_damage (defaultable)' do
      yaml = <<~YAML
        Severities: [minor, moderate, major]
        Damage Types:
          acid:
            severity: moderate
            mechanics:
              - kind: apply_acid_counter
      YAML
      with_config(yaml) do |path|
        expect { DamageTypes.new(path) }.not_to raise_error
      end
    end
  end
end
