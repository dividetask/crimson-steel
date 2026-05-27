module DiceResolution
  # Read-only view onto docs/common/dice_resolution/dice_resolution_config.yaml.
  # Stubs and validators read project-wide tunables (die size, TN
  # bounds, dice-count bounds) from here rather than baking them in.
  class Config
    DEFAULT_PATH = File.expand_path('../../docs/common/dice_resolution/dice_resolution_config.yaml', __dir__)

    attr_reader :data

    def initialize(data = {})
      @data = data
    end

    def self.load(path = DEFAULT_PATH)
      new(YAML.safe_load_file(path) || {})
    end

    def die_size;               @data.fetch('Die Size', 10);              end
    def base_target_number;     @data.fetch('Base Target Number', 6);    end
    def minimum_target_number;  @data.fetch('Minimum Target Number', 3); end
    def maximum_target_number;  @data.fetch('Maximum Target Number', 9); end
    def minimum_dice_count;     @data.fetch('Minimum Dice Count', 1);    end
    def dice_count_range;       @data.fetch('Dice Count Range', 100);    end
    def maximum_dice_count;     minimum_dice_count + dice_count_range - 1; end
  end
end
