require 'yaml'

module Proficiencies
  module Config
    DEFAULT_PATH = File.expand_path(
      '../../docs/common/proficiencies/proficiencies_config.yaml', __dir__
    )

    module_function

    def data
      @data ||= YAML.safe_load_file(DEFAULT_PATH) || {}
    end

    def attribute_contribution_divisor
      Integer(data['Attribute Contribution Divisor'] || 2)
    end

    def non_proficiency_penalty
      Integer(data['Non-Proficiency Penalty Value'] || -2)
    end

    def restricted_skills
      Array(data['Restricted Skills']).map(&:to_s)
    end

    def floor_ability
      data['Floor Ability']
    end

    def substitution_ability
      data['Substitution Ability']
    end

    def substitution_map
      data['Substitution Map'] || {}
    end

    def reset!
      @data = nil
    end
  end
end
