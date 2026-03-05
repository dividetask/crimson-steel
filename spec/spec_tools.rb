module SpecData
  attr_reader :index, :expected
  def self.clean(hash_or_array)
    return hash_or_array if hash_or_array.is_a?(Hash)
    return hash_or_array.map.with_index { |data, index| [index, data] }.to_h
  end

  def self.get_characters(); Tools.load_json('characters.json'); end

  def self.simple_test(result, expected_class, expected_params = {})
  end
end
