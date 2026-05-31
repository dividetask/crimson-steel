require 'yaml'

module Encounter
  # Loads the Encounter tunables from encounter_config.yaml. Title Case
  # keys are preserved verbatim (per project convention); typed
  # accessors wrap the raw values. Loaded once at boot.
  module Config
    PATH = File.expand_path(
      '../../docs/common/encounter/encounter_config.yaml', __dir__
    )

    module_function

    def data
      @data ||= (YAML.safe_load_file(PATH) || {})
    end

    def reset!
      @data = nil
    end

    # ---- Initiative ----
    def initiative_attribute = (data['Initiative Attribute'] || 'wis').to_sym
    def initiative_divisor   = Integer(data['Initiative Divisor'] || 2)

    # ---- Combat Pool ----
    def combat_pool_attribute = (data['Combat Pool Attribute'] || 'wis').to_sym
    def combat_pool_divisor   = Integer(data['Combat Pool Divisor'] || 2)
    def combat_pool_step      = Integer(data['Combat Pool Step'] || 4)

    # Turns Per Round indexed by Tier. A Tier beyond the array is an
    # error (the caller must extend the config), not a clamp.
    def turns_per_round = (data['Turns Per Round'] || [1])

    def turns_for_tier(tier)
      arr = turns_per_round
      raise ArgumentError, "Tier #{tier} beyond Turns Per Round array (length #{arr.length})" if tier >= arr.length
      Integer(arr[tier])
    end

    # ---- Action economy ----
    def main_action_minimum     = Integer(data['Main Action Minimum'] || 4)
    def bonus_action_minimum    = Integer(data['Bonus Action Minimum'] || 2)
    def reaction_action_minimum = Integer(data['Reaction Action Minimum'] || 2)
    def free_action_minimum     = Integer(data['Free Action Minimum'] || 0)

    # ---- Set-Value Spend ----
    def set_value_spend_ratio = Integer(data['Set Value Spend Ratio'] || 1)

    # ---- Falling damage ----
    def falling_damage_per_10_feet  = Integer(data['Falling Damage Per 10 Feet'] || 2)
    def falling_damage_threshold    = Integer(data['Falling Damage Threshold'] || 5)
    def falling_damage_bleed_constant = Integer(data['Falling Damage Bleed Constant'] || 0)

    # ---- Damage Types ----
    def damage_types = (data['damage_types'] || {})
    def metal_armor_categories = (data['Metal Armor Categories'] || [])
  end
end
