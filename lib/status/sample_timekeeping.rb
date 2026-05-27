module Status
  # Sample Timestamps for the Timekeeping sub-view of the Status page.
  # Exercises every Time of Day the Timekeeping Stub renders — early
  # morning, dawn, midday, dusk, midnight — plus a Leap Day for the
  # Calendar Date variant.
  module SampleTimekeeping
    module_function

    def timekeeping_examples
      rpd = Timekeeping.rounds_per_day
      [
        { label: 'Early morning', timestamp: { day_index: 731, round_of_day: rpd / 4 } },
        { label: 'Dawn',          timestamp: { day_index: 732, round_of_day: 3600 } },
        { label: 'Midday',        timestamp: { day_index: 732, round_of_day: rpd / 2 } },
        { label: 'Dusk',          timestamp: { day_index: 732, round_of_day: rpd * 3 / 4 } },
        { label: 'Midnight',      timestamp: { day_index: 733, round_of_day: 0 } },
        { label: 'Leap Day demo', timestamp: { day_index: 789, round_of_day: rpd / 2 } }
      ]
    end
  end
end
