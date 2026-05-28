require 'yaml'

module Creatures
  # Loads `creatures_config.yaml`. Project-wide knobs (Attributes
  # vocabulary, Tier list, per-Tier Inherent Bonuses, advancement
  # rates, etc.).
  module Config
    DEFAULT_PATH = File.expand_path(
      '../../docs/common/creatures/creatures_config.yaml', __dir__
    )

    module_function

    def data
      @data ||= YAML.safe_load_file(DEFAULT_PATH) || {}
    end

    def attributes
      data['Attributes'] || %w[str dex con int wis cha]
    end

    def attribute_keys
      attributes.map(&:to_sym)
    end

    def tiers
      data['Tiers'] || [0, 1, 2, 3, 4, 5]
    end

    def proficiency_advancement_rates
      data['Proficiency Advancement Rates'] || {}
    end

    def skill_pick_formula
      data['Skill Pick Formula']
    end

    def tier_minimum_inherent_bonus
      data['Tier Minimum Inherent Bonus'] || [0, 1, 2, 3, 4, 5]
    end

    def tier_inherent_chosen_bonus_count
      data['Tier Inherent Chosen Bonus Count'] || [0, 0, 2, 2, 2, 2]
    end

    def per_tier_inherent_chosen_bonus_amount
      data['Per-Tier Inherent Chosen Bonus Amount'] || 2
    end

    def reset!
      @data = nil
    end
  end
end
