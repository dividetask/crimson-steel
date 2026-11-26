require 'kramdown'
require 'kramdown-parser-gfm'

# Shared markdown -> HTML rendering for every documentation surface in the
# Compendium (CommonDocs concept pages, player chapters, and the DM-only
# website-design pages).
#
# Mermaid diagrams are authored as fenced ```mermaid blocks; kramdown emits
# them as <pre><code class="language-mermaid"> blocks, which a post-process
# step rewrites to <div class="mermaid"> so the client-side Mermaid script
# picks them up.
module DocMarkdown
  module_function

  def render(md)
    return '' if md.nil? || md.strip.empty?
    html = Kramdown::Document.new(md, input: 'GFM', hard_wrap: false).to_html
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
