module DiceResolution
  # Validation for a single Roll hash before the Roll Resolution
  # Stub renders it. Raises ArgumentError when any required field is
  # missing or out of the bounds set in dice_resolution_config.yaml.
  # Validates: TN within [Minimum Target Number, Maximum Target
  # Number]; dice_count a non-negative integer; die_size matching the
  # project-wide Die Size; reroll / mass_reroll / nudge well-formed
  # (sign, non-negative amount).
  #
  # The Roll Resolution Stub is a UI-facing surface, so it rejects bad
  # data loudly rather than producing a quietly wrong display.
  module Roll
    SIGNS = [:pos, :neg, 'pos', 'neg'].freeze

    module_function

    def validate!(roll, config = nil)
      config ||= DiceResolution.config
      raise ArgumentError, 'Roll must be a Hash' unless roll.is_a?(Hash)

      validate_tn!(roll, config)
      validate_dice_count!(roll, config)
      validate_die_size!(roll, config)
      validate_starting_value!(roll)
      validate_modifier!(:reroll,      roll, config)
      validate_modifier!(:mass_reroll, roll, config)
      validate_modifier!(:nudge,       roll, config)
      true
    end

    def validate_tn!(roll, config)
      tn = fetch(roll, :tn)
      raise ArgumentError, 'Roll missing tn' if tn.nil?
      min = config.minimum_target_number
      max = config.maximum_target_number
      unless tn.is_a?(Integer) && tn.between?(min, max)
        raise ArgumentError,
              "Roll tn=#{tn.inspect} must be an Integer in [#{min}, #{max}]"
      end
    end

    def validate_dice_count!(roll, config)
      dc = fetch(roll, :dice_count)
      raise ArgumentError, 'Roll missing dice_count' if dc.nil?
      unless dc.is_a?(Integer) && dc >= 0
        raise ArgumentError, "Roll dice_count=#{dc.inspect} must be a non-negative Integer"
      end
    end

    def validate_die_size!(roll, config)
      ds = fetch(roll, :die_size)
      raise ArgumentError, 'Roll missing die_size' if ds.nil?
      unless ds == config.die_size
        raise ArgumentError,
              "Roll die_size=#{ds.inspect} must equal the configured Die Size #{config.die_size}"
      end
    end

    def validate_starting_value!(roll)
      sv = fetch(roll, :starting_value)
      return if sv.nil?
      unless sv.is_a?(Integer)
        raise ArgumentError, "Roll starting_value=#{sv.inspect} must be an Integer"
      end
    end

    def validate_modifier!(kind, roll, _config)
      mod = fetch(roll, kind)
      return if mod.nil?
      raise ArgumentError, "Roll #{kind} must be a Hash" unless mod.is_a?(Hash)

      sign = fetch(mod, :sign)
      unless SIGNS.include?(sign)
        raise ArgumentError, "Roll #{kind} sign=#{sign.inspect} must be :pos or :neg"
      end

      return if kind == :mass_reroll

      amount = fetch(mod, :amount)
      unless amount.is_a?(Integer) && amount >= 0
        raise ArgumentError,
              "Roll #{kind} amount=#{amount.inspect} must be a non-negative Integer"
      end
    end

    def fetch(hash, key)
      hash[key] || hash[key.to_s]
    end
  end
end
