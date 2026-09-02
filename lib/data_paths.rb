require 'fileutils'

# Where the Campaign's mutable data lives, and whether the shipped
# example data stands behind it.
#
# Every domain that persists state (Chronicle, Encounter, Conditions,
# Atlas, Creatures, Equipment, Roll Log, Scene Round, Devices) reads and
# writes through here rather than hardcoding `data/`. Two environment
# variables move it:
#
#   CRIMSON_DATA_DIR       the directory holding the Campaign's data
#                          files. Defaults to `data/` beside the app.
#
#   CRIMSON_ISOLATED_DATA  when set, the shipped `.example` files under
#                          `docs/common/**` are NOT used as a fallback:
#                          the app sees only what the data directory
#                          itself declares.
#
# Together they let a test run boot the real server against a throwaway
# directory holding exactly the Campaign that test wants — the DM's own
# `data/` is neither read nor written, and no example Creature wanders
# into a scenario. See docs/project/browser_tests.md.
#
# Both are read once, at boot. Nothing changes for a normal run with
# neither set.
module DataPaths
  DEFAULT_DIR = File.expand_path('../data', __dir__).freeze

  module_function

  def dir
    @dir ||= File.expand_path(ENV['CRIMSON_DATA_DIR'].to_s.empty? ? DEFAULT_DIR : ENV['CRIMSON_DATA_DIR'])
  end

  def path(name)
    File.join(dir, name)
  end

  # False when the app is running against an isolated Campaign.
  def example_fallback?
    ENV['CRIMSON_ISOLATED_DATA'].to_s.empty?
  end

  # The file a domain should read: its own data file when that exists,
  # otherwise the shipped example — unless the Campaign is isolated, in
  # which case there is nothing to read and the domain starts empty.
  def source(data_path, example_path)
    return data_path if data_path && File.exist?(data_path)
    return nil unless example_fallback?
    example_path if example_path && File.exist?(example_path)
  end

  # Test seam — re-read the environment. Only useful in-process; a server
  # booted with the variables set never needs it.
  def reset!
    @dir = nil
  end
end
