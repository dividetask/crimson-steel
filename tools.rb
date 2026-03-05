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
end
