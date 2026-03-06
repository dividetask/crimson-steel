require_relative 'character'

module CharacterHelpers
  def get_info(character)
    CharacterSheet.new(character)
  end

  def h(text)
    Rack::Utils.escape_html(text.to_s)
  end
end
