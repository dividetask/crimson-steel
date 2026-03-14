require 'json'

module Tools
  def self.load_json(filename)
    file_path = File.join(File.dirname(__FILE__), 'data', filename)
    return [] unless File.exist?(file_path)
    JSON.parse(File.read(file_path))
  end

  def self.save_json(filename, data)
    file_path = File.join(File.dirname(__FILE__), 'data', filename)
    File.write(file_path, JSON.pretty_generate(data))
  end

  def self.next_item_id
    items = load_json('equipment.json')
    return 1 if items.empty?
    items.map { |i| i['item_id'].to_i }.max + 1
  end
end
