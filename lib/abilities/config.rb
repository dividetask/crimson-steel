module Abilities
  # Read-only view onto docs/common/abilities/abilities_config.yaml plus
  # the cross-domain damage-type name set (owned by Combat). Validators
  # and resolvers read tunables and vocabulary lists from here rather
  # than baking them in.
  class Config
    DEFAULT_PATH = File.expand_path('../../docs/common/abilities/abilities_config.yaml', __dir__)
    COMBAT_PATH  = File.expand_path('../../docs/common/combat/combat_config.yaml', __dir__)

    attr_reader :data, :damage_type_names

    def initialize(data = {}, damage_type_names: [])
      @data = data || {}
      @damage_type_names = damage_type_names
    end

    def self.load(path = DEFAULT_PATH, combat_path: COMBAT_PATH)
      data = YAML.safe_load_file(path) || {}
      damage_types = []
      if combat_path && File.exist?(combat_path)
        combat = YAML.safe_load_file(combat_path) || {}
        damage_types = (combat['damage_types'] || {}).keys
      end
      new(data, damage_type_names: damage_types)
    end

    def mana_cost_per_tier;     @data['Mana Cost Per Tier'] || {};        end
    def action_aliases;         @data['Action Aliases'] || {};            end
    def real_time_aliases;      @data['Real-Time Aliases'] || {};         end
    def range_formulas;         @data['Range Formulas'] || {};            end
    def default_reach_feet;     @data.fetch('Default Reach Feet', 5);     end
    def casting_skills;         @data['Casting Skills List'] || {};       end
    def universal_casting_skills; @data['Universal Spell Casting Skills'] || []; end
    def save_attributes;        @data['Save Attributes List'] || [];      end
    def save_outcome_keys;      @data['Save Outcome Keys'] || [];         end
    def properties;             @data['Properties'] || {};                end
    def spell_schools;          @data['Spell Schools'] || {};             end
    def item_forms;             @data['Item Forms'] || {};                end
    def universal_item_forms;   @data['Universal Item Forms'] || [];      end
    def area_shapes;            @data['Area Shapes'] || {};               end
    def ability_types;          @data['Catalog Ability Types'] || [];     end
    def trigger_events;         @data['Trigger Events'] || [];            end
    def bonus_types;            @data['Bonus Types List'] || {};          end

    # A casting skill is valid if it names a key directly, or if a family
    # key (one ending in `_`) is a prefix of it.
    def casting_skill?(skill)
      s = skill.to_s
      return true if casting_skills.key?(s)
      casting_skills.keys.any? { |k| k.to_s.end_with?('_') && s.start_with?(k.to_s) }
    end

    def damage_type?(name)
      @damage_type_names.empty? || @damage_type_names.include?(name.to_s)
    end
  end
end
