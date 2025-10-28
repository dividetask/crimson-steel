require 'json'

class DataStore
  attr_accessor :var1, :var2, :var3, :var4, :var5
  
  def initialize(filename)
    @filename = filename
    File.write(@filename, '{}') unless File.exist?(@filename)
    data = JSON.parse(File.read(@filename))
    data.each { |key, value| instance_variable_set("@#{key}", value) }
  end
  
  def save
    data = instance_variables.reject { |v| v == :@filename }.map { |v| [v.to_s.delete('@'), instance_variable_get(v)] }.to_h
    File.write(@filename, JSON.pretty_generate(data))
  end
end
