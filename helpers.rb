require_relative 'character'

module CharacterHelpers
  def get_info(character)
    CharacterSheet.new(character)
  end

  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end

  def format_casting_time(val)
    v = val.to_f
    return "Free" if v == 0
    return "Bonus Action" if v == 0.5
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
