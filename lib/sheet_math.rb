require 'creatures'
require 'proficiencies'
require 'proficiencies/compute'
require 'conditions'
require 'dice_resolution'
require_relative 'creature_sheet'

# The math behind the numbers on the character sheet, written out for display
# (the tablet's "?" — docs/project/android_app.md → Character sheet). Every
# value comes from the domain that owns it; this module only words it.
#
# An explanation is { title:, lines: [String] }, plus `table:` ({ head:, rows:,
# foot: }, all Strings) and `note:` where there is one. nil when it cannot be
# built: a missing explanation never breaks the sheet.
module SheetMath
  module_function

  MINUS = '−'.freeze

  # { hp:, mana:, toxicity:, damage_reduction:, damage_resilience:, combat_pool: }
  # for CreatureSheet's vitals; an entry that cannot be built is left out.
  def vitals(accessor, vitals)
    defense = vitals[:defense_breakdown] || {}
    {
      hp:                hit_points(accessor, vitals),
      mana:              mana(accessor),
      toxicity:          toxicity(accessor, vitals),
      damage_reduction:  defense('Damage Reduction', defense[:damage_reduction]),
      damage_resilience: defense('Damage Resilience', defense[:damage_resilience]),
      combat_pool:       combat_pool(vitals[:combat_pool_breakdown])
    }.compact
  end

  def hit_points(accessor, vitals)
    guard do
      b = accessor.hit_points_breakdown
      lines = ["Tier #{b[:tier]}: #{formula_text(b[:formula], b[:vars])} = #{b[:base]}"]
      lines << "#{b[:base]} #{signed_term(b[:modifiers])} from modifiers = #{b[:total]}" unless b[:modifiers].zero?
      state = CreatureSheet.conditions_for(accessor.id)&.state
      lines << used_line(b[:total], state ? state.hp_damage.values.sum : 0, 'damage')
      temp = vitals[:temp_hp].to_i
      lines << "+#{temp} temporary" if temp.positive?
      explanation('Hit Points', lines)
    end
  end

  def mana(accessor)
    guard do
      b = accessor.mana_breakdown
      parts = [b[:base]]
      lines = ["Tier #{b[:tier]}: #{formula_text(b[:formula], b[:vars])} = #{b[:base]}"]
      b[:classes].each do |c|
        next if c[:amount].zero?
        lines << "#{class_name(c[:class_key])} #{c[:level]} × #{c[:per_level]} per level = #{c[:amount]}"
        parts << c[:amount]
      end
      unless b[:modifiers].zero?
        lines << "Modifiers: #{signed(b[:modifiers])}"
        parts << b[:modifiers]
      end
      lines << "#{sum_text(parts)} = #{b[:total]}" if parts.length > 1
      state = CreatureSheet.conditions_for(accessor.id)&.state
      lines << used_line(b[:total], state ? state.mana_spent : 0, 'spent')
      explanation('Mana', lines)
    end
  end

  # The Toxicity Threshold (conditions_design.md): the Attribute, times the
  # Tier when the config scales it. Tier 0 counts as 0.5.
  def toxicity(accessor, vitals)
    guard do
      cond = CreatureSheet.conditions_for(accessor.id) or next nil
      cha  = accessor.attribute_value(:cha)
      tier = accessor.tier
      rule = if !cond.catalog.toxicity_threshold_tier_scaled? then "#{cha} CHA"
             elsif tier.zero? then "#{cha} CHA × 0.5 (Tier 0)"
             else "#{cha} CHA × Tier #{tier}"
             end
      explanation('Magic Toxicity', ["Threshold: #{rule} = #{vitals.dig(:toxicity, :threshold)}"])
    end
  end

  # One source per line, from CreatureSheet#defense_math's components.
  def defense(title, breakdown)
    guard do
      next nil unless breakdown
      parts = Array(breakdown[:components])
      lines = parts.each_with_index.map do |c, i|
        amount = c[:amount].to_i
        text = "#{i.zero? ? amount : signed_term(amount)} #{c[:label]}"
        c[:applied] == false ? "#{text} (does not stack)" : text
      end
      lines = ['No sources'] if lines.empty?
      lines << "= #{breakdown[:total]}" if parts.length > 1
      explanation(title, lines)
    end
  end

  # The Budget, then the Buy as a price table — the web sheet's Combat Pool
  # popup (creatures_minimal_stub.md § 3), from CreatureSheet#combat_pool_breakdown.
  def combat_pool(breakdown)
    guard do
      next nil unless breakdown
      turns = breakdown[:turns]
      lines = [
        "#{breakdown[:martial_ranks]} martial × 2 + #{breakdown[:attribute]} " \
        "#{breakdown[:attribute_key].to_s.upcase} = #{breakdown[:before_turns]}",
        "#{breakdown[:before_turns]} ÷ #{turns} #{turns == 1 ? 'turn' : 'turns'} per round = #{breakdown[:budget]} Budget"
      ]
      rows = Array(breakdown[:blocks]).map do |b|
        dice = b[:from] == b[:to] ? b[:from].to_s : "#{b[:from]}–#{b[:to]}"
        [dice, b[:cost_each].zero? ? 'free' : b[:cost_each].to_s, b[:spent].to_s, b[:left].to_s]
      end
      explanation('Combat Pool', lines,
                  table: { head: %w[Dice Each Cost Left], rows: rows,
                           foot: ["#{breakdown[:size]} dice", '', breakdown[:cost].to_s, breakdown[:remaining].to_s] },
                  note: "Next die costs #{breakdown[:next_die_cost]}")
    end
  end

  # Where an Attribute's score comes from. `row` is one CreatureSheet
  # attributes_table row.
  def attribute(row)
    guard do
      parts = Array(row[:breakdown])
      next nil if parts.empty?
      sum   = parts.sum { |c| c[:amount].to_i }
      terms = parts.each_with_index.map do |c, i|
        amount = c[:amount].to_i
        "#{i.zero? ? amount : signed_term(amount)} #{c[:label]}"
      end.join(' ')
      lines = [parts.length > 1 ? "#{terms} = #{sum}" : terms]
      lines << 'Never below 1' if sum < 1
      lines << "Conditions make it #{row[:score]}" if [sum, 1].max != row[:score]
      explanation(row[:attr], lines)
    end
  end

  # An Attribute Check: half the Attribute is its Prowess (CreatureSheet), no ranks.
  def check(row)
    guard do
      lines = ["Prowess: #{row[:score]} #{row[:key].to_s.upcase} ÷ 2 = #{row[:half]}"]
      lines.concat(translation_lines(row[:half]))
      lines.concat(target_number_lines(competency(row.dig(:check, :bonus))))
      explanation("#{row[:attr]} check", lines)
    end
  end

  def save(accessor, row)
    guard do
      attr  = row[:key].to_sym
      b     = Proficiencies::Compute.breakdown(key: "#{attr}_save", creature: accessor, attribute_override: attr)
      lines = roll_lines(accessor, b, save_modifiers(row))
      Array(row.dig(:save, :tokens)).select { |t| t[:conditional] }.each do |t|
        lines << "#{t[:type]}: #{signed(t[:amount].to_i)} against some effects only, not counted"
      end
      explanation("#{row[:attr]} save", lines)
    end
  end

  # The Save bonuses that always apply, as Bonus/Penalty list entries — what
  # the Save Roll is built with. Conditional ones (e.g. against poison) are not.
  def save_modifiers(row)
    Array(row.dig(:save, :tokens)).reject { |t| t[:conditional] }
                                  .map { |t| [(t[:type] || 'Resistance').to_s, t[:amount].to_i] }
  end

  def skill(accessor, key)
    guard do
      b = Proficiencies::Compute.breakdown(key: key, creature: accessor)
      explanation(CreatureSheet.pretty_skill_name(key.to_s),
                  roll_lines(accessor, b, Proficiencies::Compute.skill_modifiers_for(accessor, key.to_s)))
    end
  end

  # ---- wording ----------------------------------------------------------

  # Ranks, Prowess, dice and bonus, then the TN, for a Skill or Save.
  # `b` is Proficiencies::Compute.breakdown; `modifiers` the Roll's other
  # Bonus/Penalty list entries ([type, amount]).
  def roll_lines(accessor, b, modifiers)
    lines = []
    if b[:source_key] != b[:key]
      lines << "#{CreatureSheet.titleize_ability(Proficiencies::Config.substitution_ability)}: " \
               "#{CreatureSheet.pretty_skill_name(b[:source_key])} stands in"
    end
    lines.concat(rank_lines(accessor, b[:source_key]))
    if b[:floor_ranks] > b[:base_ranks]
      lines << "#{CreatureSheet.titleize_ability(Proficiencies::Config.floor_ability)}: at least #{ranks(b[:floor_ranks])}"
    end
    half = "#{b[:attribute_value]} #{b[:attribute].to_s.upcase} ÷ #{Proficiencies::Config.attribute_contribution_divisor}"
    lines << if b[:ranks].zero?
               "Prowess: #{half} = #{b[:prowess]}"
             else
               "Prowess: #{ranks(b[:ranks])} + #{b[:attribute_contribution]} (#{half}) = #{b[:prowess]}"
             end
    lines.concat(translation_lines(b[:prowess]))
    lines << "Untrained: #{signed(b[:penalty])}, so #{signed(b[:bonus] + b[:penalty])}" unless b[:penalty].zero?
    modifiers.each { |type, amount| lines << "#{type}: #{signed(amount.to_i)}" }
    lines.concat(target_number_lines(competency(b[:bonus] + b[:penalty]) + modifiers))
  end

  # One line per Class: the Proficiency Category it advances the key at (the
  # skill progression rate) and the ranks that gives.
  def rank_lines(accessor, key)
    return [] unless accessor.respond_to?(:rank_sources)
    sources = accessor.rank_sources(key).reject { |s| s[:category].nil? }
    lines = sources.map do |s|
      who = "#{class_name(s[:class_key])} #{s[:level]}"
      if s[:rate]
        "#{who} · #{rate_text(s[:rate])} = #{ranks(s[:ranks])}"
      else
        "#{who} · not trained (#{rate_text(s[:category])} if trained)"
      end
    end
    counted = sources.select { |s| s[:rate] }
    lines << "#{sum_text(counted.map { |s| s[:ranks] })} = #{ranks(counted.sum { |s| s[:ranks] })}" if counted.length > 1
    lines
  end

  # "Aligned: floor(5 × level ÷ 3)" — the formula as creatures_config.yaml gives it.
  def rate_text(rate)
    name    = rate.to_s.capitalize
    formula = Creatures::Config.proficiency_advancement_rates[name]
    formula ? "#{name}: #{formula.to_s.gsub('*', '×').gsub('/', '÷')}" : name
  end

  # Prowess into a bonus and dice (dice_resolution_design.md → Translate Skill
  # Prowess into Roll inputs).
  def translation_lines(prowess)
    cfg = DiceResolution.config
    dice, bonus = DiceResolution.translate_prowess(prowess)
    over = dice - cfg.minimum_dice_count
    ["Bonus: #{number(prowess)} ÷ #{cfg.dice_count_range} = #{signed(bonus)}, #{over} left over",
     "Dice: #{cfg.minimum_dice_count} + #{over} = #{dice}"]
  end

  # The TN the list gives, and the Starting Value when the TN hits its limit.
  def target_number_lines(list)
    base = DiceResolution.config.base_target_number
    net  = DiceResolution.net_modifier(DiceResolution.with_ascendancy(list))
    tn   = DiceResolution.compute_target_number(list)
    return ["TN: #{base}"] if net.zero?
    lines = []
    lines << 'Bonuses of one type do not stack' if net != list.sum { |_type, amount| amount.to_i }
    line = "TN: #{base} #{net.positive? ? MINUS : '+'} #{net.abs} = #{base - net}"
    sv = tn[:starting_value]
    return lines << line if sv.zero?
    lines << "#{line}, #{sv.positive? ? 'raised' : 'lowered'} to #{tn[:tn]}"
    lines << if sv.positive?
               "Starts with #{sv} free #{sv == 1 ? 'success' : 'successes'}"
             else
               "Starts with #{-sv} #{sv == -1 ? 'failure' : 'failures'}"
             end
  end

  def competency(bonus)
    bonus.to_i.zero? ? [] : [['Competency', bonus.to_i]]
  end

  # A formula with its values filled in: "2 * con" → "2 × 17 CON".
  def formula_text(formula, vars)
    Creatures::Formula.tokenize(formula.to_s).map do |type, value|
      case type
      when :num   then value.to_s
      when :ident then "#{vars[value.to_sym]} #{Creatures::Config.attributes.include?(value) ? value.upcase : value}"
      else { '*' => '×', '/' => '÷', '-' => MINUS }.fetch(value, value)
      end
    end.join(' ').gsub('( ', '(').gsub(' )', ')')
  end

  # "34 − 5 damage = 29"; nil when nothing is used up.
  def used_line(max, used, word)
    return nil unless used.positive?
    return "#{used} #{word}, more than the #{max}" if used > max
    "#{max} #{MINUS} #{used} #{word} = #{max - used}"
  end

  # "7 + 12 − 2": the first amount bare, the rest signed.
  def sum_text(amounts)
    amounts.each_with_index.map { |a, i| i.zero? ? number(a) : signed_term(a) }.join(' ')
  end

  def signed_term(n) = "#{n.negative? ? MINUS : '+'} #{n.abs}"
  def signed(n)      = n.negative? ? "#{MINUS}#{n.abs}" : "+#{n}"
  def number(n)      = n.negative? ? "#{MINUS}#{n.abs}" : n.to_s
  def ranks(n)       = "#{n} #{n == 1 ? 'rank' : 'ranks'}"

  def class_name(key)
    key.to_s.split('_').map(&:capitalize).join(' ')
  end

  def explanation(title, lines, table: nil, note: nil)
    out = { title: title.to_s, lines: lines.compact }
    out[:table] = table if table
    out[:note]  = note if note
    out
  end

  def guard
    yield
  rescue StandardError
    nil
  end
end
