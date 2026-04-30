require 'fileutils'

# DataBootstrap — copies docs/<domain>/<file>.yaml.example to its
# data/<file>.yaml target whenever the data file doesn't exist
# yet. Idempotent: existing data files are never overwritten.
#
# This is the seam that lets us delete code-level defaults that
# duplicate YAML. Once bootstrap has run, every lib can trust
# that its config file exists and read straight from YAML.
#
# Hooked from spec/spec_helper.rb (so the test suite always
# starts from a clean baseline) and from app.rb (so production
# / development both get the same treatment).
module DataBootstrap
  ROOT = File.expand_path('..', __dir__)

  # Mapping of example → data target. The example filenames don't
  # always match their data targets exactly (e.g. conditions
  # config example is named conditions_config.yaml.example but
  # the lib loads conditions.yaml), so the mapping is explicit
  # rather than convention-based.
  MAPPING = {
    'docs/abilities/abilities_config.yaml.example'             => 'data/abilities_config.yaml',
    'docs/abilities/abilities_data.yaml.example'               => 'data/abilities_data.yaml',
    'docs/advancement/advancement_config.yaml.example'         => 'data/advancement.yaml',
    'docs/character/character_data.yaml.example'               => 'data/characters.yaml',
    'docs/combat/combat_config.yaml.example'                   => 'data/combat_rules.yaml',
    'docs/combat/combat_data.yaml.example'                     => 'data/combat.yaml',
    'docs/conditions/conditions_config.yaml.example'           => 'data/conditions.yaml',
    'docs/damage_types/damage_types_config.yaml.example'       => 'data/damage_types.yaml',
    'docs/dice_resolution/dice_resolution_config.yaml.example' => 'data/dice_resolution.yaml',
    'docs/equipment/equipment_config.yaml.example'             => 'data/equipment_config.yaml',
    'docs/equipment/loot.yaml.example'                         => 'data/loot.yaml',
    'docs/equipment/loot_tables.yaml.example'                  => 'data/loot_tables.yaml',
    'docs/equipment/notes-loot.yaml.example'                   => 'data/notes-loot.yaml',
    'docs/equipment/shops.yaml.example'                        => 'data/shops.yaml',
    'docs/map_images_config.yaml.example'                      => 'data/map_images.yaml',
    'docs/race/race_config.yaml.example'                       => 'data/races.yaml',
    'docs/skills/skills_config.yaml.example'                   => 'data/skills.yaml'
  }.freeze

  # Returns the list of data files copied on this call.
  def self.bootstrap!(root: ROOT, log: nil)
    copied = []
    MAPPING.each do |src_rel, dst_rel|
      src_path = File.join(root, src_rel)
      dst_path = File.join(root, dst_rel)
      next unless File.exist?(src_path)
      next if File.exist?(dst_path)
      FileUtils.mkdir_p(File.dirname(dst_path))
      FileUtils.cp(src_path, dst_path)
      copied << dst_rel
      log.puts "DataBootstrap: copied #{src_rel} → #{dst_rel}" if log
    end
    copied
  end
end
