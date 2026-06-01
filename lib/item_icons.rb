require 'yaml'

# Item Icon Map — the data-driven Item Type -> icon filename mapping read
# from docs/common/equipment/item_icons.yaml. Consumed by the Store and
# Inventory stubs (via item_icon_web_path). Items absent from the map fall
# back to the slug convention; see lib/routes/store.rb.
module ItemIcons
  PATH = File.expand_path('../docs/common/equipment/item_icons.yaml', __dir__)

  module_function

  # { "Item Type" => "file.svg" }. Memoized; loaded once at boot.
  def map
    @map ||= load
  end

  def load(path = PATH)
    data = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
    (data['icons'] || {}).each_with_object({}) { |(k, v), h| h[k.to_s] = v.to_s }
  end

  def reset!
    @map = nil
  end
end
