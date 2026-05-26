require 'kramdown'

# Read + render the canonical test markdown files that ship under
# docs/common/. Surfaced on the Status page underneath each
# corresponding stub so the DM can see, in plain prose, what the
# stub-driven domain is supposed to do.
module TestDocs
  PATHS = {
    'dice'       => File.expand_path('../docs/common/dice_resolution/dice_resolution_tests.md', __dir__),
    'check'      => File.expand_path('../docs/common/check_resolution/check_resolution_tests.md', __dir__),
    'conditions' => File.expand_path('../docs/common/conditions/conditions_tests.md', __dir__)
  }.freeze

  TITLES = {
    'dice'       => 'Dice Resolution — Tests',
    'check'      => 'Check Resolution — Tests',
    'conditions' => 'Conditions — Tests'
  }.freeze

  module_function

  def render_for(view_key)
    path = PATHS[view_key]
    return nil unless path && File.exist?(path)
    Kramdown::Document.new(File.read(path, encoding: 'UTF-8')).to_html
  end

  def title_for(view_key)
    TITLES[view_key]
  end
end
