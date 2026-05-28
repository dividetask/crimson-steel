require_relative '../creatures/advancement'

module Proficiencies
  # Ranks computation per creatures_design.md `Ranks Computation` +
  # `Skill Rate Resolution`. Inputs are a (class_key, level, skill_key,
  # trained:) tuple — i.e. one Class Entry's contribution to one
  # Skill. Aggregating across Class Entries (a multi-class Creature's
  # total ranks for a skill) is the caller's job.
  module Ranks
    module_function

    # Returns :aligned / :unaligned / :opposed / nil. nil means the
    # Creature gains no ranks from this Class for the given skill key
    # (untrained, or the class doesn't categorize it at all). The
    # input skill_key must not end in `_` (no bare Set Skill keys).
    def skill_rate(class_key, skill_key, trained:)
      return nil unless trained

      cls = Creatures::Advancement.look_up_class(class_key)
      return nil unless cls

      opposed   = cls['opposed_proficiencies']   || []
      aligned   = cls['aligned_proficiencies']
      unaligned = cls['unaligned_proficiencies']

      return :opposed if matches_any?(skill_key, opposed)

      if aligned
        # Inclusion form (also the merged form for an Archetype that
        # declares aligned_proficiencies on top of an inverse-form
        # parent — see creatures_tests.md `game_chess` case).
        return matches_any?(skill_key, aligned) ? :aligned : :unaligned
      elsif unaligned
        # Inverse form.
        return matches_any?(skill_key, unaligned) ? :unaligned : :aligned
      else
        :unaligned
      end
    end

    # Class Level × Proficiency Advancement Rate. Floors apply per
    # the design.
    def apply_rate(level, rate)
      case rate
      when :aligned   then 5 * level / 3
      when :unaligned then level
      when :opposed   then 2 * level / 3
      else 0
      end
    end

    # Convenience: rate × level for one Class's contribution.
    def ranks_for_skill(class_key, level, skill_key, trained:)
      rate = skill_rate(class_key, skill_key, trained: trained)
      apply_rate(level, rate || :_none)
    end

    # Set-Skill-aware membership test: `perform_` in a list matches
    # `perform_sing`. Exact match also wins.
    def matches_any?(skill_key, list)
      list.any? do |entry|
        entry == skill_key || (entry.end_with?('_') && skill_key.start_with?(entry))
      end
    end
  end
end
