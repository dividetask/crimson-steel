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

    CLOSED_BLOCKS = {
      'Weapons'    => 'Weapon',
      'Armor'      => 'Armor',
      'Ammunition' => 'Ammunition',
      'Currency'   => 'Currency'
    }.freeze

    OPEN_BLOCKS = {
      'Items'        => 'Item',
      'Consumables'  => 'Consumable',
      'Books'        => 'Item',
      'Misc Items'   => 'Item',
      'Tattoos'      => 'Tattoo',
      'Poison Vials' => 'Consumable',
      'Unique Items' => 'Item'
    }.freeze

    attr_reader :data

    def initialize(data = {}, spells: [], poisons: [])
      @data = data || {}
      @spells = spells || []
      @poisons = poisons || []
    end

    def self.load(path = DEFAULT_PATH, spells: :auto, poisons: :auto)
      data = YAML.safe_load_file(path) || {}
      spells = load_spells if spells == :auto
      poisons = load_poisons if poisons == :auto
      new(data, spells: spells, poisons: poisons)
    end

    def self.load_spells
      require_relative '../abilities'
      Abilities.list(type: 'spell')
    rescue StandardError
      []
    end

    def self.load_poisons
      require_relative '../conditions/catalog'
      Conditions::Catalog.load.afflictions.select do |_, rule|
        rule.is_a?(Hash) && rule['category'].to_s == 'poison'
      end.keys
    rescue ScriptError, StandardError
      []
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
    def weapon_properties ; @data['Weapon Properties'] || {}  ; end
    def ammunition_block ; @data['Ammunition'] || {}          ; end
    def weapon_categories ; @data['Weapon Categories'] || {}  ; end
    def weapon_tags   ; @data['Weapon Tags'] || {}            ; end
    def damage_type_defaults ; @data['Damage Type Defaults'] || {} ; end
    def armor_category_defaults ; @data['Armor Category Defaults'] || {} ; end
    def materials     ; @data['Materials'] || {}              ; end
    def currency      ; @data['Currency'] || {}               ; end

    # ---- Item Type lookup ----------------------------------------------

    def item_type(name, _seen = [])
      found = raw_item_type(name.to_s) or return nil
      base_name = found[:definition]['inherits_from']
      return found if base_name.nil? || base_name.to_s.empty? || _seen.include?(base_name.to_s)
      base = item_type(base_name.to_s, _seen + [name.to_s]) or return found
      # Borrow the base's traits (slot, category, and — via the icon resolver
      inherited = base[:definition].reject { |k, _| k == 'base_price' }
      merged = inherited.merge(found[:definition])
      { definition: merged, category: (found[:definition]['category'] || found[:category] || base[:category]).to_s }
    end

    def raw_item_type(name)
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
      if (defn = generated_forms[name])
        return { definition: defn, category: defn['category'] }
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
      generated_forms.each { |name, defn| out << name if defn['category'] == category }
      out
    end

    # ---- autogenerated Spell-Form Item Types ---------------------------
    def spell_forms
      @spell_forms ||= build_spell_forms(@spells)
    end

    def poison_forms
      @poison_forms ||= build_poison_forms(@poisons)
    end

    def generated_forms
      @generated_forms ||= poison_forms.merge(spell_forms)
    end

    private

    def build_spell_forms(spells)
      forms = {}
      Array(spells).each do |sp|
        next unless sp.is_a?(Hash)
        spell = sp['name']
        next if spell.nil? || spell.to_s.empty?
        tier  = sp['tier']
        items = Array(sp['items']).map(&:to_s)
        forms["Scroll of #{spell}"] = consumable_form(spell, tier)
        forms["Wand of #{spell}"]   = wand_form(spell, tier)
        forms["Potion of #{spell}"] = consumable_form(spell, tier) if items.include?('potion')
        forms["Oil of #{spell}"]    = consumable_form(spell, tier) if items.include?('oil')
      end
      forms
    end

    def consumable_form(spell, tier)
      d = { 'spell' => spell, 'category' => 'Consumable', 'innately_usable' => true }
      d['tier'] = tier unless tier.nil?
      d
    end

    def wand_form(spell, tier)
      d = { 'spell' => spell, 'category' => 'Item', 'slot' => 'hands',
            'grants_spell' => true, 'hide_tier' => true }
      d['tier'] = tier unless tier.nil?
      d
    end

    def build_poison_forms(poisons)
      forms = {}
      Array(poisons).each do |key|
        next if key.nil? || key.to_s.empty?
        display = key.to_s.split('_').map(&:capitalize).join(' ')
        forms["Vial of #{display}"] = { 'poison' => key.to_s, 'category' => 'Consumable' }
      end
      forms
    end

    public

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

    def property(name)
      weapon_property(name) || armor_property(name)
    end

    def property_cost(name)
      p = property(name)
      p && p['cost']
    end

    def ammunition(name)
      (@data['Ammunition'] || {})[name.to_s]
    end

    private

    def int_keyed(map)
      map.each_with_object({}) do |(k, v), h|
        h[k.is_a?(Integer) ? k : Integer(k)] = v
      end
    end
  end
end
