require 'securerandom'

class Check < Roll
  attr_reader :check_sym, :success_mod

  def initialize(check_sym, number_of_dice, success_mod, die_values = {})
		@check_sym, @success_mod = check_sym, success_mod
		super(number_of_dice, die_values)
		@dice_results += success_mod
  end
end

class BaseRoll < Serializable
  attr_reader :dice_rolls
  @@deck = (1..10).to_a
  @@cheat_values = []

  def initialize(number_of_dice); @dice_rolls = self.class.roll_dice(number_of_dice); end
	def self.cheat cheat_values; @@cheat_values = cheat_values; end
	def self.get_rand; return @@cheat_values.shift unless @@cheat_values.empty? ; return @@deck.shuffle!(random: SecureRandom)[0]; end
	def self.roll_dice(number_of_dice); return Array.new(number_of_dice.to_i) { self.get_rand }; end
end

class InitiativeRoll < BaseRoll
  attr_reader :character

  def initialize(character, number_of_dice); @character = character; super(number_of_dice); end
	def to_s; return @dice_rolls.sort.reverse.map { |v| v == 10 ? 'X' : v.to_s }.join; end

		#combatants is expected to be a <Hash>, with each key a <Symbol> and each value a <Integer>
	def self.roll(statuses); return turn_order(multi_roll(statuses)); end

	def to_i
		digits_before_decimal = 5
  	sorted = @dice_rolls.sort.reverse.map { |die| die - 1 }
		sorted << 9 # Tiebreaker, A [5, 1, 1, 1] vs B [5, 1]    this ensures A goes first
  	return sorted.map.with_index { |die, i| die.to_f * (10 ** (digits_before_decimal-i)) }.sum
	end

	private
		#combatants is expected to be a <Array>, with each value a <InitiativeRoll>
	def self.turn_order(init_array); return init_array.sort_by { |init_roll| -1 * init_roll.to_i }; end
	def self.multi_roll(statuses); statuses.uniq { |status| status.character }.map { |status| InitiativeRoll.new(status.character, status.initiative) }; end
end

class Roll < BaseRoll
  attr_reader :dice_results, :die_values

  def initialize(number_of_dice, die_values = {})
		# number_of_dice 					is expected to be nil or an integer
		# dice_values 					 	is expected to be nil or a hash with zero or more of the following keys: fumble, crit, target, success, default
		@die_values = {fumble: -1, crit: 2, target: 9, success: 1, default: 0}.merge(die_values || {})
		super(number_of_dice)
		@dice_results = @dice_rolls.sum do |r| 
			r == 1 ? @die_values[:fumble] : r == 10 ? @die_values[:crit] : r >= @die_values[:target] ? @die_values[:success] : @die_values[:default]
		end
  end
end

