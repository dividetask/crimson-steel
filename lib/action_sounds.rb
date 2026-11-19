require 'yaml'

# Sounds tied to actions (docs/project/action_sounds.md): Ability or Spell
# name → an mp3 in public/sounds/, listed in config/action_sounds.yml. The
# list is re-read when the file changes, so a new sound needs no restart.
module ActionSounds
  CONFIG = File.expand_path('../config/action_sounds.yml', __dir__).freeze
  DIR = File.expand_path('../public/sounds', __dir__).freeze

  module_function

  def normalize(name) = name.to_s.downcase.gsub(/[^a-z0-9]+/, '')

  # name → file, from the config (empty when it is missing or broken).
  def table
    mtime = File.exist?(CONFIG) ? File.mtime(CONFIG) : nil
    return @table if @table && @mtime == mtime
    @mtime = mtime
    raw = mtime ? (YAML.safe_load(File.read(CONFIG)) rescue nil) : nil
    @table = (raw.is_a?(Hash) ? raw : {}).to_h { |k, v| [normalize(k), v.to_s] }
  end

  # The URL path of the sound for an action name, or nil (no sound, or its
  # file is missing).
  def path_for(name)
    # An item that holds a Spell ("Scroll of Fireball") plays the Spell's sound.
    file = table[normalize(name)] || table[normalize(name.to_s.sub(/\A(scroll|potion|oil|wand|ring)\s+of\s+/i, ''))]
    return nil if file.nil? || file.empty? || file.include?('/') || file.include?('..')
    File.file?(File.join(DIR, file)) ? "/sounds/#{file}" : nil
  end
end
