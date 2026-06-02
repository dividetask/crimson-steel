require 'yaml'

module Atlas
  # Loads the Atlas tunables from atlas_config.yaml. Title Case keys are
  # preserved verbatim (per project convention); typed accessors wrap the
  # raw values. State (maps, tokens, zones) lives in atlas_data.json, not
  # here — this file is rules-only. Loaded once at boot.
  module Config
    PATH = File.expand_path(
      '../../docs/common/atlas/atlas_config.yaml', __dir__
    )

    module_function

    def data
      @data ||= (YAML.safe_load_file(PATH) || {})
    end

    def reset!
      @data = nil
    end

    # ---- Tokens ----
    def default_token_size = (data['Default Token Size'] || 1)

    # ---- Grid ----
    def default_grid_type = (data['Default Grid Type'] || 'square').to_s

    # ---- Zoom (display hints) ----
    def suggested_initial_zoom = (data['Suggested Initial Zoom'] || 1)
    def minimum_zoom           = (data['Minimum Zoom'] || 0.1)
    def maximum_zoom           = (data['Maximum Zoom'] || 32)
  end
end
