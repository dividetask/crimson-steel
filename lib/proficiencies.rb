require 'yaml'

# Proficiencies domain (partial). Currently implements:
#   - Skill catalog loader (skills.yaml) with Prefix Match for Set Skills.
#   - Skill Rate Resolution + ranks computation (Proficiencies::Ranks).
#
# Not yet implemented:
#   - Direct Prowess / Substituted Prowess / Compute Roll inputs entry point.
#   - Floor Ability / Substitution Map handling.
# These will land alongside the rest of the Creatures domain.
module Proficiencies
  SKILLS_PATH = File.expand_path(
    '../docs/common/proficiencies/skills.yaml', __dir__
  )
  CONFIG_PATH = File.expand_path(
    '../docs/common/proficiencies/proficiencies_config.yaml', __dir__
  )

  module_function

  def skills
    @skills ||= (YAML.safe_load_file(SKILLS_PATH) || {})['Skills'] || {}
  end

  def config
    @config ||= YAML.safe_load_file(CONFIG_PATH) || {}
  end

  # Look up a Skill catalog entry by key. Applies Prefix Match: an
  # exact key wins, otherwise the longest Set Skill key (ending `_`)
  # that prefixes the queried key. Returns nil when nothing matches.
  def look_up(key)
    return skills[key] if skills.key?(key)
    best = nil
    skills.each_key do |k|
      next unless k.end_with?('_')
      next unless key.start_with?(k)
      best = k if best.nil? || k.length > best.length
    end
    best && skills[best]
  end

  # Driving attribute (e.g. :str) for a skill key, or nil when the
  # key doesn't resolve in the catalog.
  def attribute_for(key)
    entry = look_up(key)
    entry && entry['attribute'].to_sym
  end

  def reset!
    @skills = nil
    @config = nil
  end
end

require_relative 'proficiencies/ranks'
