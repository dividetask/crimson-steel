# Surface the canonical test markdown files that ship under
# docs/common/ on the Status page below the matching stub. The
# content is meant to *describe* what the stub-driven domain does
# — it doesn't need fancy markdown rendering; we just escape the
# source and let a styled <pre> block preserve its formatting.
# This keeps the project free of any markdown-rendering gem.
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
    text = File.read(path, encoding: 'UTF-8')
    %(<pre class="tests-doc-pre">#{escape(text)}</pre>)
  end

  def title_for(view_key)
    TITLES[view_key]
  end

  def escape(s)
    s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
