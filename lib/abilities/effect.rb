module Abilities
  # Effect-string classification and deferred-damage evaluation.
  #
  # Every Effect string is exactly one of:
  #   { kind: :none }                              for "0" / "none"
  #   { kind: :damage, ... }  (a Damage Object)    for "<expr> [severity] damage"
  #   { kind: :effect, name: <string> }            otherwise
  module Effect
    SEVERITIES = %w[minor moderate major].freeze
    DAMAGE_RE = /\A\s*(.+?)\s+(?:(#{SEVERITIES.join('|')})\s+)?damage\s*\z/.freeze

    module_function

    # context is the Effect Hash (resolved), augmented by the caller with
    # `rank` / `tier`. damage_type is the Ability's resolved scalar Damage
    # Type (Aspect-axis Abilities pick the per-aspect value before calling).
    def classify(str, context: {}, damage_type: nil)
      s = str.to_s.strip
      return { kind: :none } if s == '0' || s == 'none'

      if (m = DAMAGE_RE.match(s))
        {
          kind: :damage,
          formula: m[1].strip,
          damage_type: damage_type,
          severity: m[2] && m[2].to_sym,
          context: stringify(context)
        }
      else
        { kind: :effect, name: s }
      end
    end

    # Evaluate a Damage Object. success / critical / attribute are
    # caller-supplied (defender save results, or caster roll results).
    # Negative totals clamp to 0.
    def evaluate_damage(obj, success: 0, critical: 0, attribute: 0)
      ctx = (obj[:context] || {}).dup
      ctx['success'] = success
      ctx['critical'] = critical
      ctx['attribute'] = attribute
      value = Formula.evaluate(obj[:formula], ctx)
      value = value.floor if value.is_a?(Float)
      value.negative? ? 0 : value
    end

    def stringify(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end
  end
end
