
module TestStuff2
	@char, @skill, @attr = nil

  def self.quarter_mod(char, attr); return char[attr] / 4; end
  def self.method_missing(method, *args)
binding.irb
	end
  def self.method_added(method_name)
    return if @wrapping  # Prevent infinite recursion
binding.irb
    
    original_method = method(method_name)
    params = original_method.parameters.map { |_, name| name }
    
    @wrapping = true
    define_singleton_method(method_name) do |*args|
      # Set instance variables from parameter names
      params.each_with_index do |param_name, i|
        instance_variable_set("@#{param_name}", args[i])
      end
      
      # Call private version
      send("private_#{method_name}")
    end
    @wrapping = false
  end
end

module TestStuff3
  @char, @skill, @attr = nil
  
def self.singleton_method_added(method_name)
  return if @wrapping
  return if method_name == :singleton_method_added
  return if method_name.to_s.start_with?('private_')
  
  original_method = method(method_name)
  params = original_method.parameters.map { |_, name| name }
  
  @wrapping = true
binding.irb
  define_singleton_method(method_name) do |*args|
    params.each_with_index { |param_name, i| instance_variable_set("@#{param_name}", args[i]) }
    send("private_#{method_name}")
  end
  @wrapping = false
end
  
  def self.quarter_mod(char, attr); end
  def self.skill_ranks(char, skill); end
  
  private
  
  def self.private_quarter_mod
    @char[@attr] / 4
  end
  
  def self.private_skill_ranks
    # implementation
  end
end






class DataStore
	attr_accessor :character_list

	def initialize(filename)
		@filename = "#{filename.to_s}.json"
		if File.exist?(@filename)
			data = JSON.parse(File.read(@filename))
			data.each do |key, value|
				instance_variable_set("@#{key}", Serializable.deserialize_value(value))
			end
		else
			@character_list = []
		end
	end

	def save
		data = instance_variables.reject { |v| v == :@filename }.map do |v|
			[v.to_s.delete('@'), Serializable.serialize_value(instance_variable_get(v))]
		end.to_h
		File.write(@filename, JSON.pretty_generate(data))
	end
end

class Serializable

  def self.serialize_value(value)
    case value
    when Symbol
      {'_type' => 'symbol', '_value' => value.to_s}
    when Serializable
      {'_class' => value.class.name, '_data' => value.to_hash_for_datastore}
    when Hash
			# Serialize both keys and values, store as array of [key, value] pairs
			serialized_pairs = value.map { |k, v| [serialize_value(k), serialize_value(v)] }
			{'_type' => 'hash', '_pairs' => serialized_pairs}
    when Array
      value.map { |item| serialize_value(item) }
    when String, Numeric, TrueClass, FalseClass, NilClass
      value
    else
      value.to_s
    end
  end

	def self.deserialize_value(value)
		case value
		when Hash
			if value['_type'] == 'symbol'
				value['_value'].to_sym
			elsif value['_type'] == 'hash'
				# Reconstruct hash from [key, value] pairs
				result = {}
				value['_pairs'].each do |k, v|
					result[deserialize_value(k)] = deserialize_value(v)
				end
				result
			elsif value['_class']
				Object.const_get(value['_class']).from_hash(value['_data'])
			else
				# Plain hash, deserialize values only
				value.transform_values { |v| deserialize_value(v) }
			end
		when Array
			value.map { |item| deserialize_value(item) }
		else
			value
		end
	end

  def self.from_hash(data)
    obj = allocate
    data.each { |k, v| obj.instance_variable_set("@#{k}", deserialize_value(v)) }
    obj
  end

  def to_hash_for_datastore
    instance_variables.map { |v| [v.to_s.delete('@'), self.class.serialize_value(instance_variable_get(v))] }.to_h
  end
end


def character_creation_menu(data)
	if data.character_list && !data.character_list.empty?
		olga = data.character_list.first
		name = olga.name
		gender = olga.gender
		character_type = olga.character_sheet.character_type
		character_class = olga.character_sheet.character_class
		level = olga.character_sheet.level
		str = olga.character_sheet.str
		dex = olga.character_sheet.dex
		con = olga.character_sheet.con
		int = olga.character_sheet.int
		wis = olga.character_sheet.wis
		cha = olga.character_sheet.cha
		skills = olga.character_sheet.skills
	else
		name = "Olga"
		gender = Gender.f
		character_type = :PC
		character_class = :barbarian
		level = 3
		str, dex, con, int, wis, cha = 16, 14, 16, 10, 12, 9
		skills = {melee: 3, ranged: 2}
	end
  
  loop do
    system('clear')
    puts "=== Character Creator ==="
    puts "1. Name: #{name}"
    puts "2. Gender: #{gender.to_s}"
    puts "3. Type: #{character_type}"
    puts "4. Class: #{character_class}"
    puts "5. Level: #{level}"
    puts "6. STR: #{str}"
    puts "7. DEX: #{dex}"
    puts "8. CON: #{con}"
    puts "9. INT: #{int}"
    puts "10. WIS: #{wis}"
    puts "11. CHA: #{cha}"
    puts "12. Skills: #{skills}"
    puts "13. Save and Exit"
    puts "14. Cancel"
    print "\nSelect option: "
    
    choice = gets.chomp.to_i
    
    case choice
    when 1 then (print "Name: "; name = gets.chomp)
		when 2 then (print "Gender (m/f): "; input = gets.chomp.downcase; gender = input == 'm' ? Gender.m : input == 'f' ? Gender.f : gender)
    when 3 then (print "Type: "; character_type = gets.chomp.to_sym)
    when 4 then (print "Class: "; character_class = gets.chomp.to_sym)
    when 5 then (print "Level: "; level = gets.chomp.to_i)
    when 6 then (print "STR: "; str = gets.chomp.to_i)
    when 7 then (print "DEX: "; dex = gets.chomp.to_i)
    when 8 then (print "CON: "; con = gets.chomp.to_i)
    when 9 then (print "INT: "; int = gets.chomp.to_i)
    when 10 then (print "WIS: "; wis = gets.chomp.to_i)
    when 11 then (print "CHA: "; cha = gets.chomp.to_i)
    when 12 then (print "Skills (e.g., melee:3,ranged:2): "; skills = gets.chomp.split(',').map { |s| k,v = s.split(':'); [k.to_sym, v.to_i] }.to_h)
    when 13
      stats = CharacterStats.new(character_type, character_class, level, str, dex, con, int, wis, cha, skills)
      char = Character.new(name, gender, stats, [])
      data.character_list ||= []
			existing_index = data.character_list.find_index { |c| c.name == name }
			if existing_index
				data.character_list[existing_index] = character
			else
				data.character_list << character
			end
      data.save
      puts "Character saved!"
      break
    when 14
      puts "Cancelled"
      break
    end
  end
end

data = DataStore.new('campaign')
character_creation_menu(data)

