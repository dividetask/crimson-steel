require 'json'

module DiceResolution
  # Generates public/js/configData.js from the dice resolution YAML so the
  # browser modules and the Node test suite read one source of truth
  # instead of a hand-maintained copy. Run at server startup (see app.rb);
  # the generated file is also committed so `node --test` works without
  # booting the Ruby server.
  module ConfigJsGenerator
    OUTPUT = File.expand_path('../../public/js/configData.js', __dir__)

    # Maps YAML keys to the camelCase keys the JS DiceConfig expects.
    # failure_modifier / critical_modifier are per-Roll defaults from the
    # design (not config values), so they stay in config.js.
    KEY_MAP = {
      'Die Size'                    => 'dieSize',
      'Dice Result String Encoding' => 'diceResultStringEncoding',
      'Base Target Number'          => 'baseTargetNumber',
      'Minimum Target Number'       => 'minimumTargetNumber',
      'Maximum Target Number'       => 'maximumTargetNumber',
      'Minimum Dice Count'          => 'minimumDiceCount',
      'Dice Count Range'            => 'diceCountRange',
      'Default Success Threshold'   => 'defaultSuccessThreshold',
      'Default Fumble Threshold'    => 'defaultFumbleThreshold'
    }.freeze

    module_function

    def generate(config = Config.load, output = OUTPUT)
      data = {}
      KEY_MAP.each { |yaml_key, js_key| data[js_key] = config.data[yaml_key] }
      File.write(output, render(data))
      output
    end

    def render(data)
      <<~JS
        // GENERATED FILE — do not edit by hand.
        // Produced from docs/common/dice_resolution/dice_resolution_config.yaml
        // by lib/dice_resolution/config_js_generator.rb (runs at server startup).
        export const CONFIG_DATA = #{JSON.pretty_generate(data)};
      JS
    end
  end
end
