MINOR_DAMAGE = 1
MODERATE_DAMAGE = 2
MAJOR_DAMAGE = 3

class Damage < Serializable
  attr_reader :damage_type, :damage_severity, :damage_amount
  def initialize(dt, ds, da); @damage_type, @damage_severity, @damage_amount = dt, ds, da; end
	def get_pain; return @damage_type == 3 ? @damage_amount * 2 : 0; end
end
