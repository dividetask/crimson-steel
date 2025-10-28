module Circleverse
  def meaning; return 3.14; end
end

module Universe
  extend Circleverse

  #def self.meaning; return 42; end
end

p Universe.meaning
