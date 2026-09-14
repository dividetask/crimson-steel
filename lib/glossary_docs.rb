require_relative 'common_docs'

# Parse the glossary markdown files under docs/common/ and render them
# as a single Compendium > Glossary page. Each source file becomes a
# group; ## headings become subsections; `**Term**: definition`
# paragraphs become definition-list entries. The common glossary is
# always rendered first because its definitions take precedence over
# per-domain ones (see docs/common/common_glossary.md).
#
# The per-concept glossaries are discovered, not registered: every
# `<concept>/<concept>_glossary.md` under docs/common/ is picked up, in
# concept order. A glossary with no terms (an H1 and intro prose only) is
# silently skipped, so an empty file costs nothing.
module GlossaryDocs
  COMMON_PATH = File.expand_path('../docs/common/common_glossary.md', __dir__)

  module_function

  def render
    sources.map { |src| render_source(src) }.join
  end

  # The Common Glossary first — its definitions take precedence — then one
  # entry per concept folder that carries a glossary.
  def sources
    common = [{ key: 'common', title: 'Common Glossary', path: COMMON_PATH }]
    common + CommonDocs.concepts.select(&:glossary?).map do |concept|
      { key: concept.key, title: concept.title, path: concept.glossary_path }
    end
  end

  def render_source(src)
    return '' unless File.exist?(src[:path])
    sections = parse(File.read(src[:path], encoding: 'UTF-8'))
    return '' if sections.empty?

    out = +%(<section class="glossary-source" id="glossary-#{src[:key]}">)
    out << %(<h2 class="glossary-source-title">#{escape(src[:title])}</h2>)
    sections.each do |section|
      out << %(<section class="glossary-section">)
      out << %(<h3 class="glossary-section-h">#{escape(section[:heading])}</h3>)
      out << '<dl class="glossary-list">'
      section[:terms].each do |term|
        out << %(<dt class="glossary-term">#{render_inline(term[:term])}</dt>)
        out << %(<dd class="glossary-def">#{render_inline(term[:definition])}</dd>)
      end
      out << '</dl>'
      out << '</section>'
    end
    out << '</section>'
    out
  end

  # Walk the markdown, collecting `## Heading` sections and the
  # `**Term**: definition` paragraphs that follow each one. Skips the
  # H1 and intro prose before the first `## ` heading.
  def parse(md)
    sections = []
    current  = nil

    md.lines.each do |raw|
      line = raw.chomp
      if (m = line.match(/\A## (.+)\z/))
        sections << current if current
        current = { heading: m[1], terms: [] }
      elsif current && (m = line.match(/\A\*\*(.+?)\*\*([^:]*):\s*(.+)\z/))
        # Term: handle the common case **Term**: def, and also
        # **Term** (...trailing bold tail...): def by folding the
        # tail back onto the term so the entry reads naturally.
        term = m[2].strip.empty? ? m[1] : "#{m[1]}#{m[2]}"
        current[:terms] << { term: term, definition: m[3].strip }
      end
    end
    sections << current if current
    sections
  end

  # Minimal markdown-inline → HTML: escape first, then re-introduce
  # **bold**, *italic*, and `code` so the glossary copy keeps the
  # emphasis the source docs use (e.g. *(configurable)*, `code`).
  def render_inline(text)
    s = escape(text)
    s = s.gsub(/`([^`]+)`/) { %(<code>#{Regexp.last_match(1)}</code>) }
    s = s.gsub(/\*\*([^*]+)\*\*/) { %(<strong>#{Regexp.last_match(1)}</strong>) }
    s = s.gsub(/(?<![*])\*([^*]+)\*(?![*])/) { %(<em>#{Regexp.last_match(1)}</em>) }
    s
  end

  def escape(s)
    s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
