module Encounter
  # Severity Calculation per encounter_design.md → Operations. Turns a
  # raw damage total + Damage Type into a per-Severity Hit Point Damage
  # map plus a list of post-damage side effects (acid counter, shock,
  # inflict). The caller routes the map to Conditions' APPLY_HIT_POINT_DAMAGE
  # and dispatches the side effects.
  module Severity
    SEVERITY_KEYS = %i[minor moderate major].freeze

    module_function

    # Resolve a Damage Type's effective `severity` and `mechanics` by
    # walking its `parent` chain. The entry's own fields override
    # inherited ones; mechanics inherit when the entry declares none.
    def resolve_type(name)
      catalog = Config.damage_types
      sev = nil
      mechanics = nil
      key = name.to_s
      seen = {}
      while key && catalog.key?(key) && !seen[key]
        seen[key] = true
        entry = catalog[key] || {}
        sev ||= entry['severity']
        mechanics ||= entry['mechanics']
        key = entry['parent']
      end
      { severity: sev, mechanics: mechanics || [] }
    end

    # Compute the Severity Map + side effects.
    #   raw               — raw damage integer
    #   type              — Damage Type name
    #   threshold         — Runtime Bucketing threshold (weapon/ability)
    #   damage_resilience — defender's Damage Resilience
    #   target_tags       — defender Creature tags (for upgrade_severity)
    def compute(raw:, type:, threshold: 0, damage_resilience: 0, target_tags: [])
      resolved  = resolve_type(type)
      mechanics = resolved[:severity].is_a?(Hash) ? resolved[:mechanics] : resolved[:mechanics]
      mechanics = Array(resolved[:mechanics])

      amount = raw
      sev_override = nil
      side_effects = []

      mechanics.each do |m|
        case m['kind']
        when 'damage_per_hit'
          amount += Integer(m['amount'] || 0)
        when 'damage_multiplier'
          amount = (amount * (m['factor'] || m['amount'] || 1)).floor
        when 'upgrade_severity'
          sev_override = m['to'].to_sym if condition_met?(m['when'], target_tags)
        when 'apply_acid_counter'
          side_effects << { kind: 'acid', amount: amount }
        when 'inflict'
          amt = m['amount'].to_s == 'damage_dealt' ? amount : Integer(m['amount'] || 0)
          side_effects << { kind: 'inflict', effect: m['effect'].to_s, amount: amt }
        end
      end

      amount = 0 if amount.negative?

      severity_map =
        if resolved[:severity].is_a?(Hash) && resolved[:severity]['runtime_bucketed']
          runtime_bucket(amount, threshold: threshold, damage_resilience: damage_resilience)
        else
          sev = sev_override || resolved[:severity]&.to_sym || :minor
          { sev => amount }
        end

      { severity_map: severity_map.reject { |_, v| v.to_i.zero? }, side_effects: side_effects }
    end

    # Fill Minor up to (Threshold + Damage Resilience), then Moderate up
    # to another such bucket, then everything else into Major.
    def runtime_bucket(amount, threshold:, damage_resilience:)
      bucket = threshold + damage_resilience
      bucket = 1 if bucket <= 0 # avoid a zero-width bucket dumping all into minor/major
      minor = [amount, bucket].min
      rest  = amount - minor
      moderate = [rest, bucket].min
      major = rest - moderate
      { minor: minor, moderate: moderate, major: major }
    end

    # Critical Modifier For a Damage Type — the integer to set as the
    # attacker Roll's `critical_modifier`. Reads the Type's
    # `critical_value` Mechanic (resolving the parent chain); falls back
    # to the Roll struct default of 2 when absent.
    def critical_modifier_for(type)
      mechanics = Array(resolve_type(type)[:mechanics])
      cv = mechanics.find { |m| m['kind'] == 'critical_value' }
      cv ? Integer(cv['amount']) : 2
    end

    def condition_met?(condition, target_tags)
      return false if condition.nil?
      tags = Array(target_tags).map(&:to_s)
      case condition.to_s
      when /\Atarget_has_subtype:(.+)\z/ then tags.include?(Regexp.last_match(1))
      when 'target_has_metal_armor'      then false # Equipment domain pending
      else false
      end
    end
  end
end
