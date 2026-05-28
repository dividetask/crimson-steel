module Encounter
  # Time Tick scheduling per encounter_design.md → Operations.
  module TimeTicks
    module_function

    # Time Ticks Per Round = max(Turns Per Round[tier]) across the
    # Combatants' Tiers. Empty roster → 1.
    def ticks_per_round(tiers)
      return 1 if tiers.empty?
      tiers.map { |t| Config.turns_for_tier(t) }.max
    end

    # A Combatant of Tier `tier` with T = Turns Per Round[tier] acting
    # in a Round of R Time Ticks gets the schedule
    #   [floor((R*(2i-1) + T) / (2T)) for i = 1..T]
    # the floored midpoints of T equal segments of the Round.
    def schedule(tier, ticks_per_round)
      t = Config.turns_for_tier(tier)
      r = ticks_per_round
      (1..t).map { |i| (r * (2 * i - 1) + t) / (2 * t) }
    end
  end
end
