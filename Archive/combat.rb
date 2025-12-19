MINOR_DAMAGE = 1
MODERATE_DAMAGE = 2
MAJOR_DAMAGE = 3

class Damage < Serializable
  attr_reader :type, :severity, :amount
  def initialize(dt, ds, da); @type, @severity, @amount = dt, ds, da; end
	def get_pain; return @type == MAJOR_DAMAGE ? @amount * 2 : 0; end
	def cure_damage(amount, severity)
		return amount if severity != @severity
		old = @amount
		@amount = [0, @amount - amount].max
		return amount - old
	end

	def self.calculate_damage_list(attack_action, target, other_action_list, adjust = {})
		results = []
		return [] unless attack_action.attack_hit?(other_action_list)

		total = adjust[:damage].to_i
		total += attack_action.result(other_action_list) 
		total += attack_action.weapon.get_base_weapon_damage(attack_action.char)
		total -= (adjust[:damage_reduction].to_i + other_action_list.map(&:damage_reduction_mod).max + target.get_dr(attack_action.char))

		return [] if total <= 0

		resiliance = adjust[:resiliance].to_i + other_action_list.map(&:resiliance_mod).max + target.get_resiliance
		results << Damage.new(:physical, MINOR_DAMAGE, [total, resiliance].min)
		return results if results.sum(&:amount) == total

		results << Damage.new(:physical, MODERATE_DAMAGE, [[total - results.sum(&:amount), 0].max, attack_action.weapon.get_threshold].min)
		return results if results.sum(&:amount) == total

		results << Damage.new(:physical, MAJOR_DAMAGE, [total - results.sum(&:amount), 0].max)
		return results
	end
end

class ConjuredAction < WeaponAction
	def initialize(action); super(action.get_caster, action); end
	def dice_spent; return 0 if ( (@weapon.class == ConjuredEquipment) and (!@weapon.needs_dice?) ); return super; end 
	def max_dice; return @char.skill_dice(@weapon.skill) if @weapon.class == ConjuredEquipment; return super; end
	def tn; return @char.skill_tn(@weapon, tn_mod); end
	def success_count; return @roll.to_i + [0, @char.skill_result_mod(@weapon, tn_mod)].max; end
end

class WeaponAction < EmptyAction
  attr_reader :weapon, :result_mod

	def initialize(char, action); @weapon = action; super(char, action); end
	def max_dice; return @char.attack_dice; end
	def action_costs_dice?(); return true; end
	def dice_spent; return @weapon.speed.to_i + @dice_rolled; end
	def base_bonus; return @char.attack_bonus(@weapon); end
	def tn; return @char.attack_tn(@weapon, tn_mod); end
	def success_count; return @roll.to_i + @char.attack_result_mod(@weapon, tn_mod); end
	def attack_hit?(other_action_list); return result(other_action_list) > 2; end
	def result(other_action_list); return success_count - other_action_list.sum { |action| action.success_count }; end
end

class SkillAction < EmptyAction
	# SkillAction list -> :flatfooted, :unaware, :uncanny_dodge, :primal_tenacity, :danger_sense, :dodge, :improved_uncanny_dodge
  attr_reader :roll

	def max_dice; return (@action == :dodge) ? @char.attr_dice(:dex) : 0; end
	def action_costs_dice?(); return [:dodge].include?(@action); end
	def dice_spent; return (@action == :dodge) ? @dice_rolled : 0; end
	def tn; return @char.attr_tn(:dex) if @action == :dodge; super; end
	def tn_mod; return 0; end
	def damage_reduction_mod; return (@action == :primal_tenacity) ? 4 : 0; end
	def resiliance_mod; return (@action == :danger_sense) ? 4 : 0; end
	def mana_cost; return [:danger_sense, :primal_tenacity][@action].to_i; end

	def base_bonus
		flat_bonus = {flatfooted: -2, unaware: -4, uncanny_dodge: 0}[@action]; return flat_bonus if flat_bonus; 
		return @char.attr_bonus(:dex) if @action == :dodge
		return @char.skill_bonus(:bab) if @action == :improved_uncanny_dodge
		super
	end
end

class EmptyAction
  attr_reader :char, :action, :dice_rolled, :roll, :opponent_base_bonus

	def initialize(char, action); @char, @action, @opponent_base_bonus = char, action, nil; end
	def action_costs_dice?(); return false; end

	def max_dice; return 0; end
	def dice_spent; return 0; end
	def base_bonus; return 0; end
	def tn; return 9; end
	def damage_reduction_mod; return 0; end
	def resiliance_mod; return 0; end
	def mana_cost; return 0; end

	def set_dice_rolled(dice_rolled); @dice_rolled = dice_rolled; end
	def set_roll(roll); @roll = roll; end
	def update_opponent_base_bonus(opponent_base_bonus); @opponent_base_bonus = [@opponent_base_bonus.to_i, opponent_base_bonus].max; end

	def base_bonus_str; return Tools.number_with_plus(base_bonus); end
	def roll_range; return (-@dice_rolled..(2*@dice_rolled)).to_a; end
	def tn_mod; return -@opponent_base_bonus.to_i; end
	def success_count; return @roll.to_i; end

	def handle_dice_rolled(menu_obj, dice_rolled = nil)
		return nil unless action_costs_dice? or max_dice.to_i >= 2
		set_dice_rolled(dice_rolled || menu_obj.get_number("Bonus #{base_bonus_str}, How many dice (2-#{max_dice})", (2..max_dice).to_a))
	end

	def handle_roll(menu_obj, roll = nil)
		return nil unless @dice_rolled > 0
		message = "(#{@char.name}) How many successes (TN #{tn})"
		@roll = (roll || menu_obj.get_number(message, roll_range))
	end

	def confirm_roll(menu_obj)
		input = menu_obj.get_number("(#{@char.name}) Change roll? (#{@roll})", roll_range, @roll)
		@roll = input unless ['q', :exit].include? input
	end
end

class Attack
  attr_reader :attacker, :target, :action_list, :dm_fudge, :damage_list
	def initialize(attacker); @attacker, @action_list, @damage_list, @dm_fudge = attacker, [], [], {}; end
	#def initialize(attacker, target); @attacker, @target, @action_list, @details, @mana_spent_hash = attacker, target, [], {}, {};end
	def attack_action; @action_list[0]; end
	def other_action_list; @action_list[1..-1]; end
	def defense_action; @action_list[1]; end
	def damage_notes; @details[:damage]; end
	def damage_total; @damage_list.sum { |damage| damage.amount }; end
	def total_major; @damage_list.sum { |damage| damage.severity == MAJOR_DAMAGE ? damage.amount : 0 }; end

	def prompt_user menu_obj
		get_attack_choices menu_obj
		get_ally_choices menu_obj
		get_target_choices menu_obj
		get_target_results menu_obj
		get_attack_results menu_obj
		prompt_user_confirm_results menu_obj
		save_results
	end

	def get_attack_choices(menu_obj, weapon = nil, dice_rolled = nil, target = nil)
		weapon ||= menu_obj.choose_weapon(@attacker)
		@action_list[0] = (weapon.class == ConjuredEquipment) ? ConjuredAction.new(weapon) : WeaponAction.new(@attacker, weapon)
		@action_list[0].handle_dice_rolled(menu_obj, dice_rolled)
    @target = (target || menu_obj.choose_enemy(@attacker))
	end

	def get_ally_choices(menu_obj, action = nil, dice_rolled = nil, roll = nil)
		action ||= menu_obj.choose_conjured_defense(@attacker)
		return if action == :none
		ally_action = ConjuredAction.new(action) #Assumes it is conjured. When non magic help is availible this will need additional logic
		ally_action.handle_dice_rolled(menu_obj, dice_rolled)
		ally_action.handle_roll(menu_obj, roll)

		ally_action.update_opponent_base_bonus(attack_action.base_bonus)
		attack_action.update_opponent_base_bonus(ally_action.base_bonus)

		@action_list << ally_action
	end

	def get_target_choices(menu_obj, action = nil, dice_rolled = nil, roll = nil)
		action ||= menu_obj.choose_defense_action(@target)
		@action_list[1] = (action.class == ConjuredEquipment) ? ConjuredAction.new(action) : SkillAction.new(@target, action)
    return if @action_list[1].action_costs_dice? == false
		defense_action.handle_dice_rolled(menu_obj, dice_rolled)

		defense_action.update_opponent_base_bonus(attack_action.base_bonus)
		attack_action.update_opponent_base_bonus(defense_action.base_bonus)
	end

	def get_target_results(menu_obj, roll = nil); defense_action.handle_roll(menu_obj, roll); end
	def get_attack_results(menu_obj, roll = nil); attack_action.handle_roll(menu_obj, roll); end

	def prompt_user_confirm_results menu_obj
		attack_action.confirm_roll(menu_obj)

		if WeaponAction.did_attack_hit(attack_action, other_action_list)
			@damage_list = Damage.calculate_damage_list(attack_action, other_action_list, @dm_fudge)
			old_fudge = @dm_fudge
			 
			print "Attack did #{damage_total} points of damage, #{total_major} major damage\n"
			input = menu_obj.get_number("Adjust damage? (#{@dm_fudge[:damage]})", (-20..20).to_a, @dm_fudge[:damage])
			return if ['q', :exit].include? input
			@dm_fudge[:damage] = input
			@damage_list = Damage.calculate_damage_list(attack_action, other_action_list, @dm_fudge) if old_fudge[:damage] != input

			print "Attack did #{total_major} points of major damage\n"
			input = menu_obj.get_number("Adjust resiliance? (#{@dm_fudge[:resiliance]})", (-20..20).to_a, @dm_fudge[:resiliance])
			return if ['q', :exit].include? input
			@dm_fudge[:resiliance] = input
			@damage_list = Damage.calculate_damage_list(attack_action, other_action_list, @dm_fudge) if old_fudge[:resiliance] != input
    end
	end

	def save_results
		@damage_list.each { |dmg| @target.add_damage(dmg) }
		@action_list.each { |action| action.char.spend_dice(action.dice_spent) if action.dice_spent.to_i > 0 }
		@action_list.each do |action| 
			action.char.spend_dice(action.dice_spent) if action.dice_spent.to_i > 0
			action.char.spend_mana(action.mana_cost) if action.mana_cost.to_i > 0
		end
		#@target.update_bleed(damage_notes[:bleed]) if damage_notes[:bleed].to_i > 0
	end

	#def calculate_total_damage_mod
		#@details[:damage][:total_mod] = [:base, :bonus, :result_mod, :dm_fudge].map { |sym| @details[:damage][sym] }.sum
		#@details[:damage][:total_mod] -= @details[:damage][:reduction]
	#end

	#def defense_modifies_attack_math
		#attack_action[:tn] = @attacker.attack_tn(attack_action[:weapon], -@details[:def_bonus]) # NOTE: Ally might be blocking
		#attack_action[:bonus] = @attacker.attack_bonus(attack_action[:weapon], -@details[:def_bonus])
		#attack_action[:result_mod] = @attacker.attack_result_mod(weapon, -@details[:def_bonus])

		#@details[:damage] = {}
    #@details[:damage][:base] = weapon.get_base_weapon_damage(@attacker)
    #@details[:damage][:bonus] = attack_action[:base_bonus]
    #@details[:damage][:result_mod] = attack_action[:result_mod]
		#@details[:damage][:dm_fudge] = 0

		#calculate_total_damage_mod
	#end

	#def final_math
		#attack_action = @action_list[0]
		#defense_action = @action_list[1]
		#damage_notes = @details[:damage]

		#@details[:result_sum] = attack_action[:roll] + attack_action[:result_mod] - defense_action[:roll] - defense_action[:result_mod]

		#@details[:did_attack_hit] = @details[:result_sum] >= 2
		#if @details[:did_attack_hit]
			#calculate_total_damage_mod #NOTE This is calculated twice in case the DM fudged results
			#damage_notes[:total] = @details[:result_sum] + damage_notes[:total_mod]
			#damage_notes[:minor] = [damage_notes[:total], damage_notes[:resiliance]].min
			#damage_notes[:moderate] = [[damage_notes[:total] - damage_notes[:minor], 0].max, weapon.get_threshold].min
			#damage_notes[:major] = [damage_notes[:total] - damage_notes[:minor] - damage_notes[:moderate], 0].max
		#else
			#@details[:damage] = {}
		#end
	#end
end

	#def get_attack_choices(menu_obj, weapon = nil, dice_rolled = nil, target = nil)
		#@action_list[0] = {}
		#attack_action[:char] = @attacker
		#attack_action[:weapon] = (weapon || menu_obj.choose_weapon @attacker)																										#USER PROMPT
    #attack_action[:base_bonus] = @attacker.attack_bonus(attack_action[:weapon])

		#message = "Attack Bonus #{Tools.number_with_plus(attack_action[:base_bonus])}, How many attack dice (2-#{@attacker.attack_dice})"
    #attack_action[:dice_rolled] = (dice_rolled || menu_obj.get_number(message, (2..@attacker.attack_dice).to_a)	)						#USER PROMPT
		#attack_action[:dice_spent] = attack_action[:weapon].speed + attack_action[:dice_rolled]
		#attack_action[:dice_spent] = 0 if attack_action[:weapon].class == ConjuredEquipment and !weapon.needs_dice?

    #@target = (target || menu_obj.choose_enemy @attacker)																																		#USER PROMPT
	#end
	#def get_ally_choices(menu_obj, conj_item = nil, dice_rolled = nil, roll = nil)
		#@details[:def_bonus], @details[:ally_success] = 0
		#ally_action = {}

    #ally_action[:weapon] = (conj_item || menu_obj.choose_conjured_defense)																									#USER PROMPT
    #return if ally_action[:weapon] == :none

		#ally_action[:char], caster = ally_action[:weapon].caster
		#ally_skill = ally_action[:weapon].skill
		#max_dice = caster.skill_dice(ally_skill)

		#ally_action[:base_bonus] = caster.attack_bonus(ally_action[:weapon])

		#message = "Ally Defense Bonus #{Tools.number_with_plus(ally_action[:base_bonus])}, How many defense dice (2-#{max_dice})"
    #ally_action[:dice_rolled] = (dice_rolled || menu_obj.get_number(message, (2..max_dice).to_a)	)												#USER PROMPT
		#ally_action[:dice_spent] = (weapon.needs_dice?) ? attack_action[:dice_rolled] : 0
		#ally_action[:bonus] = caster.skill_bonus(ally_skill, -attack_action[:base_bonus])
		#@details[:def_bonus] = [ally_action[:bonus], @details[:def_bonus].to_i].max

		#ally_action[:tn] = caster.skill_tn(ally_action[:weapon], -attack_action[:base_bonus])
		#message = "(Ally)How many successes (TN #{ally_action[:tn]})"
		#ally_action[:roll] = (roll || get_number(message, (-ally_action[:dice_rolled]..(2*ally_action[:dice_rolled])).to_a))	#USER PROMPT
		#ally_action[:result_mod] = caster.attack_result_mod(ally_action[:weapon], -attack_action[:base_bonus])

		#@details[:ally_success] = @details[:ally_success].to_i + ally_action[:roll]
		#@action_list << ally_action
	#end
