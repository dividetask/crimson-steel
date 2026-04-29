require_relative 'character'

# In-game (Golarion) calendar. 12 months totaling 365 days; no leap years.
# State is stored in campaign.json under "datetime" as a hash with keys
# year/month/day/hour/minute (all ints; month 1 = Abadius). Pure functions:
# call from_h to coerce a stored hash into a normalized one before any
# arithmetic.
module GameDate
  MONTHS = [
    ['Abadius',   31],
    ['Calistril', 28],
    ['Pharast',   31],
    ['Gozran',    30],
    ['Desnus',    31],
    ['Sarenith',  30],
    ['Erastus',   31],
    ['Arodus',    31],
    ['Rova',      30],
    ['Lamashan',  31],
    ['Neth',      30],
    ['Kuthona',   31]
  ].freeze

  DEFAULT = { 'year' => 4710, 'month' => 1, 'day' => 1, 'hour' => 8, 'minute' => 0 }.freeze

  module_function

  def from_h(raw)
    src = raw.is_a?(Hash) ? raw : {}
    DEFAULT.each_with_object({}) do |(key, fallback), out|
      val = src[key] || src[key.to_sym]
      out[key] = val.nil? ? fallback : val.to_i
    end
  end

  def days_in(month_idx)
    MONTHS[(month_idx - 1) % 12][1]
  end

  def month_name(month_idx)
    MONTHS[(month_idx - 1) % 12][0]
  end

  # Advance dt by `minutes` (must be >= 0) and roll over hour/day/month/year.
  def add_minutes(dt, minutes)
    total_min = dt['hour'] * 60 + dt['minute'] + minutes.to_i
    add_days = total_min / (24 * 60)
    total_min %= (24 * 60)
    out = {
      'year'   => dt['year'],
      'month'  => dt['month'],
      'day'    => dt['day'] + add_days,
      'hour'   => total_min / 60,
      'minute' => total_min % 60
    }
    while out['day'] > days_in(out['month'])
      out['day'] -= days_in(out['month'])
      out['month'] += 1
      if out['month'] > 12
        out['month'] = 1
        out['year'] += 1
      end
    end
    out
  end

  # Advance to 8:00 AM on the next calendar day, regardless of current time.
  def next_day_morning(dt)
    out = {
      'year'   => dt['year'],
      'month'  => dt['month'],
      'day'    => dt['day'] + 1,
      'hour'   => 8,
      'minute' => 0
    }
    if out['day'] > days_in(out['month'])
      out['day'] = 1
      out['month'] += 1
      if out['month'] > 12
        out['month'] = 1
        out['year'] += 1
      end
    end
    out
  end

  def format_dt(dt)
    "#{dt['day']} #{month_name(dt['month'])} #{dt['year']} — #{'%02d:%02d' % [dt['hour'], dt['minute']]}"
  end

  # Render hints for the scene's sun/moon SVG. Day runs 06:00–18:00; the
  # sun arcs from the east horizon (left) to the west horizon (right),
  # peaking at noon. The moon does the same from 18:00–06:00. Returns
  # the cx/cy of the body in a 200x80 viewport, plus a flag for which
  # body to draw.
  def sun_moon_view(dt)
    minutes = dt['hour'].to_i * 60 + dt['minute'].to_i
    is_day = minutes >= 6 * 60 && minutes < 18 * 60
    night_min = if is_day
                  0
                else
                  minutes < 6 * 60 ? minutes + 6 * 60 : minutes - 18 * 60
                end
    progress = (is_day ? (minutes - 6 * 60) : night_min) / (12.0 * 60)
    cx = 20.0 + 160.0 * progress
    cy = 70.0 - 55.0 * Math.sin(progress * Math::PI)
    { 'is_day' => is_day, 'cx' => cx.round(1), 'cy' => cy.round(1) }
  end
end

module CharacterHelpers
  # Short/full display labels for the combat-tracker condition badges.
  # Entries not listed fall back to a title-cased version of the key.
  # The full form is shown as a tooltip so abbreviations stay discoverable.
  CONDITION_LABEL_OVERRIDES = {
    'minor_strength_poison' => ['Poison', 'Minor strength poison']
  }.freeze

  def condition_label(cname)
    key = cname.to_s
    return CONDITION_LABEL_OVERRIDES[key] if CONDITION_LABEL_OVERRIDES.key?(key)
    full = key.tr('_', ' ').capitalize
    [full, full]
  end

  def get_info(character)
    CharacterSheet.new(character)
  end

  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end

  def format_casting_time(val)
    v = val.to_f
    return "Free" if v == 0
    # Casting times less than a half-action are bonus actions. Exactly 0.5
    # is a half action (used for in-combat healing/buff spells). 1 is a
    # standard action; larger values roll over to rounds/minutes/hours.
    return "Bonus Action" if v > 0 && v < 0.5
    return "Half Action" if v == 0.5
    return "Main Action" if v == 1
    return "#{(v / 3600).to_i} hour#{'s' if v >= 7200}" if v >= 3600
    return "#{(v / 60).to_i} minute#{'s' if v >= 120}" if v >= 60
    return "#{v.to_i} round#{'s' if v > 1}"
  end

  def resolve_spell_description(spell, idx, tier_val)
    spell["description"].gsub(/\{(\w+)\}/) do |match|
      var = $1
      val = spell[var] || (spell["effect_hash"] && spell["effect_hash"][var])
      next match unless val
      if val.is_a?(Array)
        val[idx].to_s
      elsif val.is_a?(String)
        eval(val.gsub("tier", tier_val.to_s)).to_s rescue val
      else
        val.to_s
      end
    end
  end
end
