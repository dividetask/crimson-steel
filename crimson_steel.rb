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
	def reset; {MINOR_DAMAGE => 2, MODERATE_DAMAGE => 5, MAJOR_DAMAGE => 2}.each { |s,a| @lysander.add_damage(Damage.new(:physical, s, a)) }; end

  def initialize(reset_database = false)
    ResetCharacters.overwrite_data if reset_database
    @data = DataStore.new('campaign')
    @menu_obj = Menu.new(@data)
		@status_list = @data.status_list.map { |status| [status.name, status] }.to_h
		@lysander = @status_list['Lysander']
		@stumpy = @status_list['Stumpy']
		@enemy = @status_list.values.last
  end

  def show_char
    @menu_obj.display_combat_status
    Tools.press_any_key
  end

  def console; binding.irb; end

	def debug
		@krak = @status_list['Kraken']
  #def get_damage(severity = nil); return @health_notes[:damage_list].select { |dmg| [nil, dmg.damage_severity].include? severity}.sum(&:damage_amount); end
#binding.irb
		@menu_obj.main_menu
	end

	def debug_combat
		p @enemy.name
		attack_obj = Attack.new(@enemy)
		attack_obj.get_attack_choices @menu_obj, @enemy.weapons.first, 4, @stumpy
		p attack_obj.target.name
		attack_obj.get_ally_choices @menu_obj, :none
		attack_obj.get_target_choices @menu_obj, :dodge, 5, 4
		attack_obj.get_target_results @menu_obj, 5
		attack_obj.get_attack_results @menu_obj, 2
		attack_obj.prompt_user_confirm_results @menu_obj
		attack_obj.save_results
	end
	
end

def run_main
	#ResetCharacters.overwrite_data
  data = DataStore.new('campaign')
  menu = Menu.new(data)
  menu.main_menu
end

#$debug_now = false

#ResetCharacters.overwrite_data
debug_obj = DebugStuff.new(false)
debug_obj.debug
#debug_obj.add_damage
#run_main
#debug_obj.print_info
#debug_obj.show_char
#run_main
p 'Done'

