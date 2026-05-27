require 'kramdown'
require 'kramdown-parser-gfm'

# Loads the player-facing explainer markdown files under docs/common/
# and renders them as HTML for the Compendium page. Each entry here
# corresponds to one left-nav item in the Compendium.
#
# Mermaid diagrams are authored as fenced ```mermaid blocks in the
# markdown; kramdown emits them as <pre><code class="language-mermaid">
# blocks, which a post-process step rewrites to <div class="mermaid">
# so the client-side Mermaid script picks them up.
module ExplainerDocs
  SOURCES = {
    'dice' => {
      title: 'Dice Resolution',
      path:  File.expand_path('../docs/common/dice_resolution/dice_resolution_explainer.md', __dir__)
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

    html = Kramdown::Document.new(
      File.read(src[:path], encoding: 'UTF-8'),
      input: 'GFM',
      hard_wrap: false
    ).to_html

    rewrite_mermaid_blocks(html)
  end

  # kramdown wraps ```mermaid in <pre><code class="language-mermaid">.
  # Mermaid's client-side renderer only picks up <div class="mermaid">,
  # so rewrite the block. We also un-escape the body since Mermaid
  # parses raw text rather than HTML.
  def rewrite_mermaid_blocks(html)
    html.gsub(%r{<pre><code class="language-mermaid">(.*?)</code></pre>}m) do
      body = Regexp.last_match(1)
                   .gsub('&lt;', '<')
                   .gsub('&gt;', '>')
                   .gsub('&quot;', '"')
                   .gsub('&#39;', "'")
                   .gsub('&amp;', '&')
      %(<div class="mermaid">#{body}</div>)
    end
  end
end
