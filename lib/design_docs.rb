require 'kramdown'
require 'kramdown-parser-gfm'
require 'explainer_docs'

# DM-only "website design" reference docs surfaced in the Compendium.
#
# Unlike the player-facing Explainer chapters (docs/common/**), these live
# under docs/website_design/** and are visible only to the DM (see
# docs/project/compendium.md). Each entry here is one DM-only left-nav item.
#
# Because they are DM-only, these pages may carry developer directives and
# notes that are stripped from the rendered page but kept in the source file:
#   * `@function <name>` declaration lines, and
#   * fenced ```test blocks (worked sample data / cases).
# Mermaid diagrams are handled exactly as in ExplainerDocs.
module DesignDocs
  SOURCES = {
    'combat' => {
      title: 'Combat',
      path:  File.expand_path('../docs/website_design/combat/combat_encounter_stub.md', __dir__)
    },
    'action_builder' => {
      title: 'Action Builder',
      path:  File.expand_path('../docs/website_design/combat/action_builder_stub.md', __dir__)
    },
    'combat_interfaces' => {
      title: 'Combat — Interfaces',
      path:  File.expand_path('../docs/website_design/combat/required_interfaces.md', __dir__)
    },
    'combat_test_data' => {
      title: 'Combat — Test Data',
      path:  File.expand_path('../docs/website_design/combat/test_data.md', __dir__)
    }
  }.freeze

  module_function

  def keys
    SOURCES.keys
  end

  def title_for(key)
    SOURCES.dig(key, :title)
  end

  def render(key)
    src = SOURCES[key]
    return nil unless src && File.exist?(src[:path])

    md = strip_directives(File.read(src[:path], encoding: 'UTF-8'))
    html = Kramdown::Document.new(md, input: 'GFM', hard_wrap: false).to_html

    # Reuse the Explainer mermaid post-process so a diagram renders the same
    # way on a DM design page as on a player-facing chapter.
    ExplainerDocs.rewrite_mermaid_blocks(html)
  end

  # Drop developer-only directives/notes before rendering. They stay in the
  # source file (for whoever is building the site) but never reach the page:
  #   * fenced ```test … ``` blocks — worked sample data / cases;
  #   * `@function <name>` declaration lines.
  def strip_directives(md)
    without_tests = md.gsub(/^[ \t]*```test\b.*?^[ \t]*```[ \t]*\n?/m, '')
    without_tests.gsub(/^[ \t]*@function\b.*(?:\n|\z)/, '')
  end
end
