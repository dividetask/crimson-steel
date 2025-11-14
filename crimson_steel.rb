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
    @active_char = @data.status_list.first
    @target_char = @data.status_list[-2]
  end

  def add_damage
    @target_char.add_damage(Damage.new(:physical, MODERATE_DAMAGE, 10))
    @target_char.update_bleed(10)
    @target_char.add_damage(Damage.new(:bonus, MODERATE_DAMAGE, 5))
    @menu.display_combat_status
  end

  def show_char
    @menu.display_combat_status
    Tools.press_any_key
  end

  def console; binding.irb; end

  def print_info
    $debug_now = true
  	p @target_char.get_remaining_hp
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

