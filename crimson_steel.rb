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

class DebugStuff
  def initialize(reset_database = false)
    ResetCharacters.overwrite_data unless reset_database
    @data = DataStore.new('campaign')
    @menu = Menu.new(@data)
    @kraken = @data.status_list[-2]
    @stumpy = @data.status_list.first
  end

  def add_damage
    @stumpy.add_damage(Damage.new(:physical, MINOR_DAMAGE, 4))
    @stumpy.add_damage(Damage.new(:physical, MODERATE_DAMAGE, 3))
    @stumpy.add_damage(Damage.new(:physical, MAJOR_DAMAGE, 2))
    @stumpy.update_bleed(10)
    @menu.display_combat_status
  end

  def show_char
    @menu.display_combat_status
    Tools.press_any_key
  end

  def console; binding.irb; end

  def print_info
    $debug_now = true
  	p @kraken.get_remaining_hp
    Tools.press_any_key
  end
end

def run_main
	#ResetCharacters.overwrite_data
  data = DataStore.new('campaign')
  menu = Menu.new(data)
  menu.main_menu
end

$debug_now = false

debug_obj = DebugStuff.new(true)
debug_obj.add_damage
#debug_obj.print_info
debug_obj.show_char
#run_main
p 'Done'

