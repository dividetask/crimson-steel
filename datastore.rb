require 'json'
require 'date'
require 'time'

class DataStore
	attr_accessor :character_list, :status_list, :initiative

	def initialize(filename)
    @character_list = []
    @initiative = nil
    @status_list = []
		@filename = "#{filename.to_s}.json"
		if File.exist?(@filename)
      Serializable.clear_cache  # Clear before loading
			data = JSON.parse(File.read(@filename))
			data.each do |key, value|
				instance_variable_set("@#{key}", Serializable.deserialize_value(value))
			end
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
  @@deserialized_objects = {}
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
        # Check if we've already deserialized this object
        object_key = "#{value['_class']}_#{value['_data'].hash}"
        @@deserialized_objects[object_key] ||= begin
          Object.const_get(value['_class']).from_hash(value['_data']).after_load()
        end
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

  def self.clear_cache
    @@deserialized_objects = {}
  end

  def to_hash_for_datastore
		vars ||= instance_variables
    vars.map { |v| [v.to_s.delete('@'), self.class.serialize_value(instance_variable_get(v))] }.to_h
  end

  def self.from_hash(data); obj = allocate; data.each { |k, v| obj.instance_variable_set("@#{k}", deserialize_value(v)) }; obj; end
	def after_load(); return self; end
end
