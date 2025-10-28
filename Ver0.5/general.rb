require 'securerandom'

class Gender
  attr_reader :gender  	# Can be read outside class, but not written
  private_class_method :new  # Makes .new private

  def initialize(gender); @gender = gender; end
  def self.male; new('M'); end
  def self.female; new('F'); end
  def self.m; new('M'); end
  def self.f; new('F'); end
  def self.it; new('?'); end
  def him_her; @gender == 'M' ? 'him' : (@gender == 'F' ? 'her' : 'it'); end
  def his_hers; @gender == 'M' ? 'his' : (@gender == 'F' ? 'hers' : 'its'); end
end

class BaseRoll
  attr_reader :dice_rolls
  @@deck = (1..10).to_a
  @@cheat_values = []

  def initialize(number_of_dice)
		# number_of_dice 					is expected to be nil or an integer
		@dice_rolls = self.class.roll_dice(number_of_dice)
  end

	def self.cheat cheat_values
		@@cheat_values = cheat_values
	end

	def self.get_rand
		return @@cheat_values.shift unless @@cheat_values.empty?
		return @@deck.shuffle!(random: SecureRandom)[0]
	end

	def self.roll_dice(number_of_dice)
		# number_of_dice 					is expected to be nil or an integer
		# returns an array of integers whose value is between 1 and 10

		return [] if (number_of_dice == nil or number_of_dice <= 0)
		return Array.new(number_of_dice) { self.get_rand }
	end
end
