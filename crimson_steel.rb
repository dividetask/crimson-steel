require 'irb'
require_relative 'declarations.rb'
require_relative 'datastore.rb'
require_relative 'roll.rb'
require_relative 'items.rb'
#require_relative 'combat.rb'
require_relative 'character.rb'
require_relative 'display.rb'
#require_relative 'general.rb'
#require_relative 'rules.rb'
#require_relative 'tests.rb'
require_relative 'reset.rb'

#class CharacterStatus
  #attr_reader :character, :health_notes, :combat_pool

	#def update_bleed(bleed_mod); @health_notes[:bleed] = [0, @health_notes[:bleed] += bleed_mod].max; end
	#def reset_combat_dice; @combat_pool[:remaining] = @combat_pool[:maximum]; end
	#def get_remaining_dice; @combat_pool[:remaining]; end
	#def spend_dice(dice_count); @combat_pool[:remaining] -= dice_count; end
	#def get_remaining_hp; return @health_notes[:maximum] + @health_notes[:damage_list].sum(&:damage_amount); end

  #def initialize(character)
	#def update_status(attack_details)


#ResetCharacters.overwrite_data

data = DataStore.new('campaign')
#Display.cycle_through_characters(data)
Display.select_characters(data)
p 'Done'

