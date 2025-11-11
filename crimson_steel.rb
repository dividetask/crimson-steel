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

#class CharacterStatus
  #attr_reader :character, :health_notes, :combat_pool

	#def update_bleed(bleed_mod); @health_notes[:bleed] = [0, @health_notes[:bleed] += bleed_mod].max; end
	#def reset_combat_dice; @combat_pool[:remaining] = @combat_pool[:maximum]; end
	#def get_remaining_dice; @combat_pool[:remaining]; end
	#def spend_dice(dice_count); @combat_pool[:remaining] -= dice_count; end
	#def get_remaining_hp; return @health_notes[:maximum] + @health_notes[:damage_list].sum(&:damage_amount); end

  #def initialize(character)
	#def update_status(attack_details)


#alpha = ResetCharacters.get_werewolf_alpha
#p alpha.dex
#p alpha.half_mod(:dex)  #7
#p alpha.ranks(:bab) #5
#p alpha.attack_dice #6
#p alpha.attack_base_tn
#p alpha.attack_bonus


#exit
  #def attack_dice; return ((half_mod(attr_sym(:bab)) + ranks(:bab) - 2) % 5) + 6; end
  #def attack_base_tn(weapon); return [4, [9, SKILL_BASE_TN[weapon.get_attack_type] + tn_mod(:bab)].min].max; end
	#def attack_bonus(weapon);

#ResetCharacters.overwrite_data

data = DataStore.new('campaign')
#Display.cycle_through_characters(data)
#Display.select_characters(data)
Display.main_menu(data)
p 'Done'

