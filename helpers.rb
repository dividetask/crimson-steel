require_relative 'character'

module CharacterHelpers
  def get_info(character)
    CharacterSheet.new(character)
  end

  def h(text)
    Rack::Utils.escape_html(text.to_s)
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
