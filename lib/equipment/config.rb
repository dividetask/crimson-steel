require 'yaml'

module Equipment
  # Read-only view onto `equipment_config.yaml`: tunables plus the
  # Item Type and Magical Property catalogs. See
  # docs/common/equipment/equipment_design.md.
  #
  # Catalog.load builds an instance from the docs directory; tests may
  # also construct a Catalog directly from an in-memory hash to
  # exercise homebrew overrides.
  class Catalog
    DEFAULT_PATH = File.expand_path(
      '../../docs/common/equipment/equipment_config.yaml', __dir__
    )

    # "Closed" blocks have a fixed Item Category; an entry's own
    # `category:` field there is a sub-category (Weapon Category, Armor
    # Category) and must not be read as the Item Category.
    CLOSED_BLOCKS = {
      'Weapons'    => 'Weapon',
      'Armor'      => 'Armor',
      'Ammunition' => 'Ammunition',
      'Currency'   => 'Currency'
    }.freeze

    # "Open" blocks let each entry declare its own Item Category via
    # `category:`, defaulting to the value below when absent.
    OPEN_BLOCKS = {
      'Items'      => 'Item',
      'Consumables'=> 'Consumable',
      'Books'      => 'Item',
      'Misc Items' => 'Item'
    }.freeze

    attr_reader :data

    def initialize(data = {})
      @data = data || {}
    end

    def self.load(path = DEFAULT_PATH)
      new(YAML.safe_load_file(path) || {})
    end

    # ---- pricing tunables ----------------------------------------------

    def default_tier_surcharge
      int_keyed(@data['Default Tier Surcharge'] || {})
    end

    def default_bonus_surcharge
      int_keyed(@data['Default Bonus Surcharge'] || {})
    end

    def magical_ammunition_divisor
      @data['Magical Ammunition Divisor'] || 100
    end

    def consumable_surcharge_divisor
      @data['Consumable Surcharge Divisor'] || 10
    end

    def innately_usable_price_multiplier
      @data['Innately Usable Price Multiplier'] || 2.0
    end

    # ---- display tunables ----------------------------------------------

    def tier_prefix_format
      @data['Tier Prefix Format'] || '+{tier}'
    end

    def tier_hidden_for
      @data['Tier Hidden For'] || []
    end

    def default_property_position
      (@data['Default Property Position'] || 'prefix').to_s
    end

    # ---- consumption tunables ------------------------------------------

    def consumable_saturation_base
      (@data.dig('Consumable Saturation', 'Base')) || []
    end

    def consumable_saturation_minimum
      (@data.dig('Consumable Saturation', 'Minimum')) || []
    end

    def lower_tier_multiplier
      (@data.dig('Consumable Saturation', 'Lower Tier Multiplier')) || 1
    end

    # ---- structural catalogs -------------------------------------------

    def slots         ; @data['Slots'] || []                 ; end
    def weapons       ; @data['Weapons'] || {}                ; end
    def armor         ; @data['Armor'] || {}                  ; end
    def ammunition_block ; @data['Ammunition'] || {}          ; end
    def weapon_categories ; @data['Weapon Categories'] || {}  ; end
    def weapon_tags   ; @data['Weapon Tags'] || {}            ; end
    def damage_type_defaults ; @data['Damage Type Defaults'] || {} ; end
    def armor_category_defaults ; @data['Armor Category Defaults'] || {} ; end
    def materials     ; @data['Materials'] || {}              ; end
    def currency      ; @data['Currency'] || {}               ; end

    # ---- Item Type lookup ----------------------------------------------

    # Returns { definition:, category: } for an Item Type name, or nil
    # when the name is not in any catalog block. The `Gem` Item Type is
    # built in and has no catalog entry.
    def item_type(name)
      name = name.to_s
      return { definition: {}, category: 'Gem' } if name == 'Gem'

      CLOSED_BLOCKS.each do |block, category|
        entries = @data[block]
        next unless entries.is_a?(Hash) && entries.key?(name)
        return { definition: entries[name] || {}, category: category }
      end
      OPEN_BLOCKS.each do |block, default_category|
        entries = @data[block]
        next unless entries.is_a?(Hash) && entries.key?(name)
        defn = entries[name] || {}
        return { definition: defn, category: (defn['category'] || default_category).to_s }
      end
      nil
    end

    def category_of(name)
      it = item_type(name)
      it && it[:category]
    end

    def definition_of(name)
      it = item_type(name)
      it && it[:definition]
    end

    # Every Item Type whose Category (as resolved above) equals the
    # given category string. Used by Magical Item generation.
    def item_types_in_category(category)
      out = []
      CLOSED_BLOCKS.each do |block, cat|
        entries = @data[block]
        out.concat(entries.keys) if entries.is_a?(Hash) && cat == category
      end
      OPEN_BLOCKS.each do |block, default_category|
        entries = @data[block]
        next unless entries.is_a?(Hash)
        entries.each do |name, defn|
          defn ||= {}
          out << name if (defn['category'] || default_category).to_s == category
        end
      end
      out
    end

    # The mundane Tier-0 Base Price of an Item Type, honoring tier-array
    # `base_price` lists (e.g. Healing Potion).
    def base_price_for(name, tier)
      defn = definition_of(name) || {}
      bp = defn['base_price']
      case bp
      when Array then bp[tier] || 0
      when nil   then 0
      else bp
      end
    end

    # ---- Property lookup -----------------------------------------------

    def weapon_property(name) ; (@data['Weapon Properties'] || {})[name.to_s] ; end
    def armor_property(name)  ; (@data['Armor Properties'] || {})[name.to_s]  ; end

    # A Property may live in either the Weapon or Armor catalog. Used
    # for cost, display, and effect lookups that don't care which.
    def property(name)
      weapon_property(name) || armor_property(name)
    end

    # The Gold cost of a Property as authored in the catalog. Stacks
    # copy this at attach time (Property Application `cost`).
    def property_cost(name)
      p = property(name)
      p && p['cost']
    end

    # ---- ammunition ----------------------------------------------------

    def ammunition(name)
      (@data['Ammunition'] || {})[name.to_s]
    end

    private

    # YAML loads integer map keys as Integers already, but JSON / test
    # hashes may use strings. Normalize to Integer keys.
    def int_keyed(map)
      map.each_with_object({}) do |(k, v), h|
        h[k.is_a?(Integer) ? k : Integer(k)] = v
      end
    end
  end
end
