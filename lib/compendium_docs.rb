# Renders the player-facing rules pages shown in the Compendium.
#
# A "chapter" is any subdirectory of docs/game_rules/ (except common/) that
# holds a <chapter>/<chapter>_overview.md. The overview is written in a small
# markup layered on top of Markdown:
#
#   [[Term]] / [[Term|shown]]  — a Glossary keyword. Renders the (shown) text
#                                with a click/hover popup carrying the plain-
#                                English definition from
#                                docs/game_rules/common/glossary.md.
#
#   {{ expression }}           — a value drawn from the chapter's
#                                <chapter>_config.yaml. The expression may name
#                                config keys and arithmetic over them. Config
#                                scalars are replaced by their value and nested
#                                formula keys are expanded; variables that are
#                                NOT config keys (the runtime inputs such as
#                                Attribute, Prowess, Dice Modifier) are kept
#                                symbolic. If nothing symbolic remains the
#                                expression is computed to a single number.
#
#   ```test … ```              — a worked test in YAML. Skipped entirely when
#                                rendering; kept in the source as documentation.
#
# See docs/website_design/compendium.md for the full design.
require 'yaml'
require 'kramdown'
require 'kramdown-parser-gfm'

module CompendiumDocs
  GAME_RULES_DIR = File.expand_path('../docs/game_rules', __dir__)
  GLOSSARY_PATH  = File.join(GAME_RULES_DIR, 'common', 'glossary.md')

  module_function

  # ---- Chapters & navigation -------------------------------------------

  # Every chapter that actually has an overview, title-cased from its
  # directory name, sorted for a stable menu order.
  def chapters
    return [] unless File.directory?(GAME_RULES_DIR)
    Dir.children(GAME_RULES_DIR)
       .reject { |name| name == 'common' }
       .select { |name| File.file?(overview_path(name)) }
       .map    { |name| { key: name, title: titleize(name) } }
       .sort_by { |c| c[:title] }
  end

  # The Compendium left-nav: one link per chapter overview, with the
  # Glossary pinned last.
  def nav_items
    items = chapters.map { |c| { key: c[:key], label: c[:title] } }
    items << { key: 'glossary', label: 'Glossary' }
    items
  end

  def view_keys
    chapters.map { |c| c[:key] } + ['glossary']
  end

  def title_for(key)
    key == 'glossary' ? 'Glossary' : titleize(key)
  end

  # ---- Overview rendering ----------------------------------------------

  # Render a chapter overview to HTML, or nil when the chapter has no
  # overview. Pipeline: drop tests -> inject {{config}} -> Markdown ->
  # restore keyword/formula tokens -> rewrite mermaid fences.
  def render_overview(key)
    path = overview_path(key)
    return nil unless File.file?(path)

    config = load_config(key)
    glossary = glossary_index
    tokens = {}

    md = File.read(path, encoding: 'UTF-8')
    md = strip_tests(md)
    md = inject_function_tags(md, tokens)
    md = inject_keywords(md, glossary, tokens)
    md = inject_variables(md, config, tokens)

    html = Kramdown::Document.new(md, input: 'GFM', auto_ids: true).to_html
    tokens.each { |tok, frag| html = html.sub(tok, frag) }
    rewrite_mermaid(html)
  end

  def overview_has_mermaid?(html)
    html.include?('class="mermaid"')
  end

  # ---- Glossary rendering ----------------------------------------------

  def render_glossary
    by_category = glossary_entries.group_by { |e| e[:category] || 'Terms' }
    out = +''
    by_category.each do |category, entries|
      out << %(<section class="glossary-section">)
      out << %(<h2 class="glossary-section-h">#{escape(category)}</h2>)
      out << '<dl class="glossary-list">'
      entries.each do |e|
        out << %(<dt class="glossary-term">#{escape(e[:term])}</dt>)
        out << %(<dd class="glossary-def">#{escape(e[:definition])}</dd>)
      end
      out << '</dl></section>'
    end
    out
  end

  # =====================================================================
  # Internals
  # =====================================================================

  def overview_path(key)
    File.join(GAME_RULES_DIR, key, "#{key}_overview.md")
  end

  def config_path(key)
    File.join(GAME_RULES_DIR, key, "#{key}_config.yaml")
  end

  def titleize(name)
    name.split(/[_-]/).map { |w| w.empty? ? w : w[0].upcase + w[1..] }.join(' ')
  end

  def load_config(key)
    path = config_path(key)
    return {} unless File.file?(path)
    data = YAML.safe_load(File.read(path)) || {}
    data.is_a?(Hash) ? data : {}
  end

  # Drop ```test … ``` fenced blocks before anything else sees them.
  def strip_tests(md)
    md.gsub(/^[ \t]*```test[^\n]*\n.*?\n[ \t]*```[ \t]*$\n?/m, '')
  end

  # ---- Function sections -----------------------------------------------

  # `@function <Name>` on its own line (right under a section heading) marks
  # that section as defining a function — the variable it calculates. It
  # renders as a small "ƒ function" badge; prose sections have none.
  def inject_function_tags(md, tokens)
    md.gsub(/^[ \t]*@function[ \t]+(.+?)[ \t]*$/) do
      name = $1.strip
      frag = %(<span class="cr-fn-tag"><span class="cr-fn-badge">ƒ function</span> ) +
             %(#{escape(name)}</span>)
      store(tokens, frag)
    end
  end

  # ---- Keywords --------------------------------------------------------

  def inject_keywords(md, glossary, tokens)
    md.gsub(/\[\[(.+?)\]\]/m) do
      term, shown = $1.split('|', 2)
      term = term.to_s.strip
      shown = (shown || term).strip
      entry = glossary[normalize(term)] || glossary[singularize(normalize(term))]
      frag =
        if entry
          %(<span class="cr-kw" tabindex="0" role="button" ) +
            %(aria-label="Definition of #{escape(entry[:term])}">#{escape(shown)}) +
            %(<span class="cr-kw-pop"><span class="cr-kw-pop-title">#{escape(entry[:term])}</span>) +
            %(<span class="cr-kw-pop-body">#{escape(entry[:definition])}</span></span></span>)
        else
          # Unknown term: render the text plainly so the page never breaks.
          escape(shown)
        end
      store(tokens, frag)
    end
  end

  # ---- Config variables & formulas ------------------------------------

  def inject_variables(md, config, tokens)
    md.gsub(/\{\{(.+?)\}\}/) do
      text, formula = resolve($1, config)
      frag = formula ? %(<code class="cr-formula">#{escape(text)}</code>) : escape(text)
      store(tokens, frag)
    end
  end

  # Resolve a {{...}} expression. Returns [text, is_formula].
  #
  # The common case is a bare config key — {{Die Size}}, {{Dice Cap Formula}} —
  # which is treated as the reference <Die Size>. Expressions may also write
  # <Name> explicitly and combine them with arithmetic.
  def resolve(expr, config)
    expr = expr.strip

    if config.key?(expr)
      val = config[expr]
      # A bare scalar key resolves straight to its value.
      return [val.to_s, false] unless val.is_a?(String) && val.include?('<')
      # A bare formula key expands at the top level — no wrapping parens.
      substituted = substitute(val, config, 0)
    else
      substituted = substitute(expr, config, 0)
    end

    if substituted =~ /[A-Za-z]/
      [tidy(substituted), true]          # still symbolic -> a formula
    else
      value = (evaluate(substituted) rescue nil)
      value.nil? ? [tidy(substituted), true] : [value.to_s, false]
    end
  end

  # Replace <Name> references: config scalars by value, config formulas by
  # their (parenthesized) expansion, everything else kept as a bare name.
  def substitute(expr, config, depth)
    return expr if depth > 25
    expr.gsub(/<([^<>]+)>/) do
      name = $1.strip
      if config.key?(name)
        val = config[name]
        if val.is_a?(String) && val.include?('<')
          '(' + substitute(val, config, depth + 1) + ')'
        else
          val.to_s
        end
      else
        name
      end
    end
  end

  def tidy(expr)
    expr.gsub(/\s+/, ' ').strip
  end

  # A small integer arithmetic evaluator (+ - * / %, parentheses). Division
  # and modulo floor, per the design-doc convention. Raises on anything it
  # doesn't understand so resolve() can fall back to the symbolic form.
  def evaluate(expr)
    tokens = expr.scan(%r{\d+|[()+\-*/%]}).reject { |t| t.strip.empty? }
    raise 'unparseable' if tokens.join != expr.gsub(/\s+/, '')
    eval_rpn(to_rpn(tokens))
  end

  PRECEDENCE = { '+' => 1, '-' => 1, '*' => 2, '/' => 2, '%' => 2 }.freeze

  def to_rpn(tokens)
    output = []
    ops = []
    tokens.each do |tok|
      if tok =~ /\A\d+\z/
        output << tok.to_i
      elsif PRECEDENCE.key?(tok)
        output << ops.pop while ops.last && PRECEDENCE[ops.last] && PRECEDENCE[ops.last] >= PRECEDENCE[tok]
        ops << tok
      elsif tok == '('
        ops << tok
      elsif tok == ')'
        output << ops.pop while ops.last && ops.last != '('
        raise 'mismatched parens' unless ops.pop == '('
      else
        raise "bad token #{tok}"
      end
    end
    output.concat(ops.reverse)
    raise 'mismatched parens' if output.include?('(')
    output
  end

  def eval_rpn(rpn)
    stack = []
    rpn.each do |tok|
      if tok.is_a?(Integer)
        stack << tok
      else
        b = stack.pop
        a = stack.pop
        raise 'bad expression' if a.nil? || b.nil?
        stack << case tok
                 when '+' then a + b
                 when '-' then a - b
                 when '*' then a * b
                 when '/' then raise('divide by zero') if b.zero?; (a.to_f / b).floor
                 when '%' then raise('mod by zero') if b.zero?; a % b
                 end
      end
    end
    raise 'bad expression' unless stack.size == 1
    stack.first
  end

  # ---- Glossary parsing -----------------------------------------------

  # Parsed Glossary entries: { category:, term:, definition: }. Recognizes
  # "## Category" headings and "**Term**: definition" lines.
  def glossary_entries
    return [] unless File.file?(GLOSSARY_PATH)
    category = nil
    File.read(GLOSSARY_PATH, encoding: 'UTF-8').each_line.each_with_object([]) do |line, acc|
      if (m = line.match(/^##\s+(.+?)\s*$/))
        category = m[1]
      elsif (m = line.match(/^\s*\*\*(.+?)\*\*\s*[:—-]\s*(.+?)\s*$/))
        acc << { category: category, term: m[1].strip, definition: m[2].strip }
      end
    end
  end

  # term (normalized) -> entry, for keyword popups. Rebuilt each render so
  # edits to the glossary show up without a restart.
  def glossary_index
    glossary_entries.each_with_object({}) { |e, h| h[normalize(e[:term])] ||= e }
  end

  def normalize(term)
    term.to_s.downcase.gsub(/\s+/, ' ').strip
  end

  # Crude singularizer for plural keyword references ("Checks" -> "check").
  def singularize(term)
    term.sub(/ies\z/, 'y').sub(/s\z/, '')
  end

  # ---- shared helpers --------------------------------------------------

  def store(tokens, frag)
    tok = "«cr#{tokens.size}»"
    tokens[tok] = frag
    tok
  end

  def rewrite_mermaid(html)
    html.gsub(%r{<pre><code class="language-mermaid">(.*?)</code></pre>}m) do
      %(<div class="mermaid">#{$1}</div>)
    end
  end

  def escape(text)
    text.to_s
        .gsub('&', '&amp;')
        .gsub('<', '&lt;')
        .gsub('>', '&gt;')
        .gsub('"', '&quot;')
  end
end
