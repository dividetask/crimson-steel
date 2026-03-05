require_relative 'character'

module CharacterHelpers
  def get_info(character)
    CharacterSheet.new(character)
  end
end
