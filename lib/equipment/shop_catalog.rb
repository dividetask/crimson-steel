require 'yaml'

module Equipment
  # Read-only catalog of Generic Shops, loaded from `shops.yaml`. Each
  # Generic Shop carries population-scaled stocking rules (per-item
  # `min_pop` / `qty_base` / `qty_per_kpop`) and a purchasing-budget
  # formula (`base_gold` + `gold_per_sqrt_pop`). See the shops.yaml
  # header and equipment_design.md "Generic Shop stocking".
  class ShopCatalog
    DEFAULT_PATH = File.expand_path(
      '../../docs/common/equipment/shops.yaml', __dir__
    )

    attr_reader :generic_shops, :state

    def initialize(generic_shops: {}, state: {})
      @generic_shops = generic_shops
      @state = state
    end

    def self.load(path = DEFAULT_PATH)
      data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      new(generic_shops: data['generic_shops'] || {}, state: data['state'] || {})
    end

    def generic_shop(id)
      @generic_shops[id.to_s]
    end

    def current_day
      @state['current_day'] || 0
    end
  end
end
