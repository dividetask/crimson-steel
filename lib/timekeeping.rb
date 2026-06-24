require 'yaml'

# Timekeeping — pure calculation. See docs/common/timekeeping/timekeeping_design.md.
#
# Holds no state. Callers pass a Timestamp `{day_index, round_of_day}`
# in and receive Calendar Date / Time of Day / advanced Timestamp out.
module Timekeeping
  module_function

  def config
    @config ||= Config.load
  end

  # Test seam — reset cached config so a spec can swap it.
  def reset_config!
    @config = nil
  end

  def with_config(cfg)
    prior = @config
    @config = cfg
    yield
  ensure
    @config = prior
  end

  # ---------- Public entry points ----------

  # Resolve a Calendar Date from a signed day_index. Returns
  # { year:, month:, day_of_month:, day_of_week: }.
  def calendar_date(day_index, cfg = config)
    day_index = Integer(day_index)
    year = cfg.default_starting_year
    remaining = day_index

    if remaining >= 0
      loop do
        len = cfg.days_per_year(year)
        break if remaining < len
        remaining -= len
        year += 1
      end
    else
      until remaining >= 0
        year -= 1
        remaining += cfg.days_per_year(year)
      end
    end

    month_lengths = cfg.month_lengths_for(year)
    month_index = 0
    while month_index < month_lengths.size && remaining >= month_lengths[month_index]
      remaining -= month_lengths[month_index]
      month_index += 1
    end

    dow_index = day_index % cfg.day_of_week_names.length
    dow_index += cfg.day_of_week_names.length if dow_index.negative?

    {
      year: year,
      month: month_index + 1,
      day_of_month: remaining + 1,
      day_of_week: cfg.day_of_week_names[dow_index]
    }
  end

  # Resolve a Time of Day from a round_of_day. Returns "HH:MM:SS".
  def time_of_day(round_of_day, cfg = config)
    round_of_day = Integer(round_of_day)
    raise ArgumentError, "round_of_day out of range" if round_of_day < 0 || round_of_day >= cfg.rounds_per_day

    seconds = round_of_day * cfg.round_length
    h = seconds / 3600
    m = (seconds % 3600) / 60
    s = seconds % 60
    format('%02d:%02d:%02d', h, m, s)
  end

  # Advance a Timestamp by signed Round and Day offsets.
  def advance(timestamp, rounds: 0, days: 0, cfg: config)
    di = Integer(timestamp[:day_index] || timestamp['day_index'])
    rod = Integer(timestamp[:round_of_day] || timestamp['round_of_day'])
    rounds = Integer(rounds)
    days = Integer(days)

    new_rounds = rod + rounds
    rpd = cfg.rounds_per_day
    day_carry = new_rounds.fdiv(rpd).floor
    new_rod = new_rounds - day_carry * rpd

    { day_index: di + day_carry + days, round_of_day: new_rod }
  end

  # ---------- Helpers exposed for callers / UI ----------

  def month_name(month_number, cfg = config)
    cfg.month_names[month_number - 1]
  end

  def rounds_per_day(cfg = config)
    cfg.rounds_per_day
  end

  # Hour of the day (0..23) for a given round_of_day. Used by the
  # Timekeeping Stub's sky region.
  def hour_of_day(round_of_day, cfg = config)
    (round_of_day * cfg.round_length) / 3600
  end

  # ---------- Inverse helpers (DM "set date/time" control) ----------

  # The signed day_index for a Calendar Date — the inverse of calendar_date.
  # Clamps the month into range; the day-of-month is taken as given (so the
  # caller can over/underflow a month deliberately, e.g. "day 0").
  def to_day_index(year:, month:, day_of_month:, cfg: config)
    year  = Integer(year)
    month = Integer(month)
    dom   = Integer(day_of_month)
    start = cfg.default_starting_year

    di = 0
    if year >= start
      (start...year).each { |y| di += cfg.days_per_year(y) }
    else
      (year...start).each { |y| di -= cfg.days_per_year(y) }
    end

    lengths = cfg.month_lengths_for(year)
    m = month.clamp(1, lengths.size)
    (0...(m - 1)).each { |i| di += lengths[i] }
    di + (dom - 1)
  end

  # The round_of_day for a clock time, clamped to [0, rounds_per_day - 1].
  def round_of_day_for(hour:, minute: 0, second: 0, cfg: config)
    seconds = Integer(hour) * 3600 + Integer(minute) * 60 + Integer(second)
    rod = seconds / cfg.round_length
    rpd = cfg.rounds_per_day
    rod.clamp(0, rpd - 1)
  end
end

require_relative 'timekeeping/config'
