# Where the server keeps its state files. CRIMSON_DATA_DIR points a run at
# another folder (the scenario runner gives each run its own empty one).
module DataDir
  DEFAULT = File.expand_path('../data', __dir__).freeze

  def self.root
    ENV['CRIMSON_DATA_DIR'].to_s.empty? ? DEFAULT : File.expand_path(ENV['CRIMSON_DATA_DIR'])
  end

  def self.path(*parts) = File.join(root, *parts)
end
