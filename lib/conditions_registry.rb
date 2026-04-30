require 'yaml'
require 'fileutils'
require 'securerandom'
require_relative 'conditions'

# ConditionsRegistry — owns one Conditions instance per character and
# persists every instance to a single YAML file so that production has
# real durable state for HP damage, afflictions, shock, acid counter,
# and named/generic effects.
#
# The on-disk layout is:
#
#   characters:
#     "1":  { hit_point_damage: {...}, afflictions: {...}, ... }
#     "2":  { ... }
#
# Keys are stringified char_ids so the file is round-trip safe across
# Ruby restarts. Each value is the dict produced by Conditions#to_dict.
#
# Conditions doesn't know how to save itself (deliberately — see
# conditions_design.md "Owned by the conditions module"). The registry
# is the smallest layer above it that owns persistence.
class ConditionsRegistry
  def initialize(state_path:, config_path:, dice_system:, severities:)
    @state_path  = state_path
    @config_path = config_path
    @dice_system = dice_system
    @severities  = severities
    @instances   = {}

    load_state!
  end

  # Returns the Conditions instance for char_id, creating one (and
  # persisting it) if none exists yet. Idempotent.
  def for_character(char_id)
    key = char_id.to_s
    @instances[key] ||= Conditions.new(
      config_path: @config_path,
      dice_system: @dice_system,
      severities:  @severities
    )
  end

  def save!
    return unless @state_path
    FileUtils.mkdir_p(File.dirname(@state_path))
    payload = {
      'characters' => @instances.transform_values(&:to_dict)
    }
    tmp = "#{@state_path}.tmp.#{SecureRandom.hex(4)}"
    File.write(tmp, payload.to_yaml)
    File.rename(tmp, @state_path)
  end

  private

  def load_state!
    return unless @state_path && File.exist?(@state_path)
    data = YAML.safe_load_file(@state_path, permitted_classes: [Symbol]) || {}
    (data['characters'] || {}).each do |char_id, dict|
      @instances[char_id.to_s] = Conditions.new(
        config_path:   @config_path,
        dice_system:   @dice_system,
        severities:    @severities,
        initial_state: dict
      )
    end
  end
end
