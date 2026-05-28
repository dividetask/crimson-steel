module Timekeeping
  # Read-only view onto docs/common/timekeeping/timekeeping_config.yaml.
  class Config
    DEFAULT_PATH = File.expand_path('../../docs/common/timekeeping/timekeeping_config.yaml', __dir__)

    attr_reader :data

    def initialize(data = {})
      @data = data
    end

    def self.load(path = DEFAULT_PATH)
      new(YAML.safe_load_file(path) || {})
    end

    def round_length;          @data.fetch('Round Length', 6); end
    def default_starting_year; @data.fetch('Default Starting Year', 4710); end
    def leap_year_interval;    @data.fetch('Leap Year Interval', 4); end
    def leap_month;            @data.fetch('Leap Month', 2); end
    def month_lengths;         @data.fetch('Month Lengths', []); end
    def month_names;           @data.fetch('Month Names', []); end
    def day_of_week_names;     @data.fetch('Day of Week Names', []); end

    def rounds_per_day
      (86400 / round_length)
    end

    def leap_year?(year)
      iv = leap_year_interval
      return false if iv.zero?
      (year % iv).zero?
    end

    def days_per_year(year)
      base = month_lengths.sum
      leap_year?(year) ? base + 1 : base
    end

    # Month lengths adjusted for a given year — the Leap Month is
    # one Day longer in Leap Years.
    def month_lengths_for(year)
      lengths = month_lengths.dup
      if leap_year?(year)
        idx = leap_month - 1
        lengths[idx] = lengths[idx] + 1
      end
      lengths
    end
  end
end
