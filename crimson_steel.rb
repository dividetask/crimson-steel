require 'irb'
require_relative 'declarations.rb'
require_relative 'datastore.rb'
require_relative 'roll.rb'
require_relative 'items.rb'
require_relative 'combat.rb'
require_relative 'character.rb'
require_relative 'display.rb'
#require_relative 'general.rb'
#require_relative 'rules.rb'
#require_relative 'tests.rb'
require_relative 'reset.rb'

ResetCharacters.overwrite_data

data = DataStore.new('campaign')
#Display.cycle_through_characters(data)
#Display.select_characters(data)
#Display.main_menu(data)
display = Menu.new(data)
display.main_menu
p 'Done'

