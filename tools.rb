module Tools
  def self.load_json(filename)
    file_path = File.join(File.dirname(__FILE__), 'data', filename)
    JSON.parse(File.read(file_path)) if File.exist?(file_path)
  end
end

