require_relative 'doc_markdown'
require_relative 'config_tables'
require_relative 'catalog_tables'

# The Common Rules: one page per concept folder under docs/common/.
#
# Every concept folder follows the same file contract (see
# docs/common/file_conventions.md):
#
#   <concept>_design.md     the merged rules document — player prose and
#                           implementer rules side by side, split by the
#                           @player / @implementation markers
#   <concept>_config.yaml   the tunable values, rendered as a table
#   <concept>_glossary.md   terms, merged into the Compendium Glossary
#   <concept>_tests.md      canonical test cases, DM-only
#
# Nothing is registered in code: the folder IS the registry. A new concept
# folder appears on the site as soon as it exists, and a folder missing a
# file renders a visible gap rather than silently not existing — that gap
# is the point, it is how a half-finished concept shows up for review.
#
# Directives, all stripped from the rendered page:
#
#   @chapter <n> [title]    the doc's place in the player's manual, and the
#                           title it carries there. Absent = not in the book.
#   @player                 following content is player-facing
#   @implementation         following content is implementer/DM-only (@dm
#                           is accepted as a synonym)
#   @function <name>        a developer declaration
#   ```test … ```           worked sample data / cases
#
# A heading resets the mode back to @implementation, so an unclosed
# @player can never leak past the section that opened it. Content carrying
# no marker is DM-only — a forgotten marker costs a paragraph in the book,
# it never puts implementer notes in front of players.
#
# Inside any document, {{Config Key}} substitutes the live value from the
# concept's own *_config.yaml (falling back to any other concept's config),
# so a worked example can never drift from the value the code reads. A `>`
# path reaches a nested value or a catalog ({{skills.yaml > Skills}}), and
# {{table: <path>}} prints one as a table.
module CommonDocs
  ROOT = File.expand_path('../docs/common', __dir__)

  # Folders under docs/common/ that are not concepts. `ui/` holds this
  # site's interface stubs — website design rather than shared rules — so
  # it carries no design/config/glossary/tests set and gets no page here.
  NON_CONCEPT_DIRS = %w[ui].freeze

  DEFAULT_MODE = :implementation

  CHAPTER_RE = /\A@chapter\s+(\d+)\s*(.*)\z/
  PLAYER_RE  = /\A@player\s*\z/
  IMPL_RE    = /\A@(?:implementation|dm)\s*\z/
  HEADING_RE = /\A(\#{1,6})\s+(.*)\z/
  FENCE_RE   = /\A\s*(?:```|~~~)/

  Block = Struct.new(:kind, :level, :mode, :text, keyword_init: true)

  Concept = Struct.new(
    :key, :title, :dir, :chapter, :chapter_title,
    :design_path, :config_path, :tests_path, :glossary_path,
    keyword_init: true
  ) do
    def design?   = design_path   && File.exist?(design_path)
    def config?   = config_path   && File.exist?(config_path)
    def tests?    = tests_path    && File.exist?(tests_path)
    def glossary? = glossary_path && File.exist?(glossary_path)
    def chapter?  = !chapter.nil?
  end

  module_function

  # ---- discovery -------------------------------------------------------

  # Every concept folder, alphabetical by key. Rebuilt per call so a doc
  # edit shows up on reload without restarting the server.
  def concepts
    Dir.children(ROOT)
       .select { |name| File.directory?(File.join(ROOT, name)) }
       .reject { |name| NON_CONCEPT_DIRS.include?(name) }
       .sort
       .map    { |name| build_concept(name) }
  end

  def build_concept(name)
    dir    = File.join(ROOT, name)
    design = File.join(dir, "#{name}_design.md")
    meta   = File.exist?(design) ? front_matter(File.read(design, encoding: 'UTF-8')) : {}

    Concept.new(
      key:           name,
      title:         meta[:title] || humanize(name),
      dir:           dir,
      chapter:       meta[:chapter],
      chapter_title: meta[:chapter_title] || meta[:title] || humanize(name),
      design_path:   design,
      config_path:   File.join(dir, "#{name}_config.yaml"),
      tests_path:    File.join(dir, "#{name}_tests.md"),
      glossary_path: File.join(dir, "#{name}_glossary.md")
    )
  end

  def find(key)
    concepts.find { |c| c.key == key }
  end

  # The player's manual, in reading order. Concepts with no @chapter are
  # not in the book and do not appear.
  def chapters
    concepts.select(&:chapter?).sort_by { |c| [c.chapter, c.key] }
  end

  # Nav order for the concept list: numbered concepts first, in chapter
  # order, then the unnumbered ones alphabetically. Numbered and unnumbered
  # entries never interleave — a gap in the numbering should read as a gap,
  # not as an unnumbered entry that happens to sort between two chapters.
  def in_nav_order
    numbered, unnumbered = concepts.partition(&:chapter?)
    numbered.sort_by { |c| [c.chapter, c.key] } + unnumbered.sort_by(&:title)
  end

  # Chapter numbers claimed by more than one concept. Rendered as a
  # warning badge in the nav rather than silently resolved.
  def duplicate_chapters
    chapters.group_by(&:chapter).select { |_, cs| cs.size > 1 }.keys.sort
  end

  # ---- parsing ---------------------------------------------------------

  # Pull the doc-level metadata without a full parse: the @chapter
  # directive and the H1 (minus any trailing "— Design").
  def front_matter(md)
    meta = {}
    in_fence = false
    md.each_line do |raw|
      line = raw.chomp
      in_fence = !in_fence if line.match?(FENCE_RE)
      next if in_fence

      if (m = line.match(CHAPTER_RE))
        meta[:chapter] = m[1].to_i
        meta[:chapter_title] = m[2].strip unless m[2].strip.empty?
      elsif !meta.key?(:title) && (m = line.match(HEADING_RE)) && m[1].length == 1
        meta[:title] = m[2].strip.sub(/\s*[—-]\s*Design\s*\z/, '')
      end
    end
    meta
  end

  # Split a design doc into heading and content blocks, each content block
  # carrying the visibility mode in force where it was written.
  def parse_blocks(md)
    blocks   = []
    mode     = DEFAULT_MODE
    in_fence = false
    buffer   = []

    flush = lambda do
      text = buffer.join
      blocks << Block.new(kind: :content, mode: mode, text: text) unless text.strip.empty?
      buffer = []
    end

    md.each_line do |raw|
      line = raw.chomp

      if line.match?(FENCE_RE)
        in_fence = !in_fence
        buffer << raw
        next
      end

      if in_fence
        buffer << raw
        next
      end

      if line.match?(CHAPTER_RE)
        next
      elsif line.match?(PLAYER_RE)
        flush.call
        mode = :player
      elsif line.match?(IMPL_RE)
        flush.call
        mode = :implementation
      elsif (m = line.match(HEADING_RE))
        flush.call
        blocks << Block.new(kind: :heading, level: m[1].length, mode: nil, text: m[2].strip)
        # A heading closes any open marker: each section declares its own
        # tracks, so a missing marker can never leak across sections.
        mode = DEFAULT_MODE
      else
        buffer << raw
      end
    end
    flush.call
    blocks
  end

  # Drop developer-only directives before parsing. They stay in the source
  # file but never reach the page.
  def strip_directives(md)
    md.gsub(/^[ \t]*```test\b.*?^[ \t]*```[ \t]*\n?/m, '')
      .gsub(/^[ \t]*@function\b.*(?:\n|\z)/, '')
  end

  # Which blocks a given audience sees. The DM sees everything (player
  # passages included, so the merged doc can be reviewed whole). A player
  # sees @player content, plus every heading that still has something
  # underneath it.
  def blocks_for(blocks, audience)
    return blocks if audience == :dm

    blocks.each_with_index.select do |block, i|
      if block.kind == :content
        block.mode == :player
      else
        heading_visible?(blocks, i)
      end
    end.map(&:first)
  end

  # A heading survives for players when any content before the next
  # same-or-higher-level heading is player-facing.
  def heading_visible?(blocks, index)
    level = blocks[index].level
    blocks[(index + 1)..].each do |block|
      break if block.kind == :heading && block.level <= level
      return true if block.kind == :content && block.mode == :player
    end
    false
  end

  # ---- substitution ----------------------------------------------------

  # Config values visible to {{Key}} in this concept's docs: the concept's
  # own config wins, every other concept's config is the fallback.
  def substitution_values(concept)
    global.merge(ConfigTables.values_for(concept.config_path))
  end

  def global
    concepts.each_with_object({}) do |concept, acc|
      acc.merge!(ConfigTables.values_for(concept.config_path)) { |_k, old, _new| old }
    end
  end

  # What a path resolves to when it names nothing.
  MISSING = Object.new.freeze

  # Replace {{…}} with live rule data.
  #
  #   {{Key}}                 a config value
  #   {{Key > field}}         a value nested inside one
  #   {{file.yaml > Key}}     a value in a catalog (any YAML file in a
  #                           concept folder; the concept's own wins)
  #   {{<path> + n}}          a number, offset — so a worked example follows
  #                           the value when it is retuned. Only a bare
  #                           integer offset: this is not an expression
  #                           language.
  #   {{table: <path> | …}}   the value as a table (CatalogTables)
  #
  # A path that names nothing renders as a visible marker rather than
  # silently disappearing.
  def substitute(text, values, concept: nil)
    text.gsub(/\{\{([^}\n]+)\}\}/) do
      expr = Regexp.last_match(1).strip
      next table(expr.delete_prefix('table:'), values, concept) if expr.start_with?('table:')

      path, op, offset = expr.match(/\A(.*?)\s*(?:([+-])\s*(\d+))?\z/).captures
      path  = path.strip
      value = lookup(path, values, concept)
      next missing("unknown config key: #{path}") if value.equal?(MISSING)

      if op.nil?
        inline_value(value)
      elsif value.is_a?(Numeric)
        (op == '+' ? value + offset.to_i : value - offset.to_i).to_s
      else
        missing("#{path} is not a number")
      end
    end
  end

  def missing(message)
    %(<span class="doc-missing-key">[#{ConfigTables.escape(message)}]</span>)
  end

  # `rows` may itself be a path to a list, so a table can follow another
  # part of the rules ("the playable races") instead of repeating it.
  def table(spec, values, concept)
    path, *rest = spec.split('|').map(&:strip)
    options = rest.to_h { |option| option.split(':', 2).map { |part| part.to_s.strip } }

    data = lookup(path, values, concept)
    return missing("unknown table: #{path}") if data.equal?(MISSING)

    if options['rows']
      listed = lookup(options['rows'], values, concept)
      options['rows'] = listed.is_a?(Array) ? listed : options['rows'].split(',').map(&:strip)
    end
    CatalogTables.render(data, options) || missing("#{path} is not a table")
  end

  def lookup(path, values, concept = nil)
    head, *rest = path.split('>').map(&:strip)
    node = if head.to_s.end_with?('.yaml')
             file = catalog_file(head, concept)
             file ? catalog(file) : MISSING
           else
             values.fetch(head, MISSING)
           end
    rest.each do |segment|
      break if node.equal?(MISSING)
      node = step(node, segment)
    end
    node
  end

  def step(node, segment)
    case node
    when Hash
      return node[segment] if node.key?(segment)
      number = Integer(segment, exception: false)
      number && node.key?(number) ? node[number] : MISSING
    when Array
      index = Integer(segment, exception: false)
      index && index >= 0 && index < node.length ? node[index] : MISSING
    else
      MISSING
    end
  end

  # A catalog is named by file name alone and found in a concept folder.
  def catalog_file(name, concept)
    return nil unless name == File.basename(name)
    own = concept && File.join(concept.dir, name)
    return own if own && File.file?(own)
    Dir.glob(File.join(ROOT, '*', name)).min
  end

  def catalog(path)
    @catalogs ||= {}
    mtime = File.mtime(path)
    entry = @catalogs[path]
    return entry[1] if entry && entry[0] == mtime

    data = begin
      YAML.safe_load(File.read(path, encoding: 'UTF-8'), aliases: true)
    rescue Psych::Exception
      MISSING
    end
    @catalogs[path] = [mtime, data]
    data
  end

  def inline_value(value)
    case value
    when Array, Hash then CatalogTables.cell(value)
    else value.to_s
    end
  end

  # ---- rendering -------------------------------------------------------

  # The rules body of a concept, for one audience. Player passages are
  # wrapped for the DM so the merged document can be reviewed at a glance.
  def render_design(concept, audience:)
    return nil unless concept.design?

    md     = strip_directives(File.read(concept.design_path, encoding: 'UTF-8'))
    values = substitution_values(concept)
    blocks = blocks_for(parse_blocks(md), audience)
    return '' if blocks.empty?

    blocks.map { |block| render_block(block, audience, values, concept) }.join
  end

  def render_block(block, audience, values, concept)
    if block.kind == :heading
      text = block.text
      # The player's manual carries the chapter's own title, not the
      # design document's "— Design" heading.
      text = concept.chapter_title if audience == :player && block.level == 1
      return DocMarkdown.render("#{'#' * block.level} #{substitute(text, values, concept: concept)}")
    end

    html = DocMarkdown.render(substitute(block.text, values, concept: concept))
    if audience == :dm && block.mode == :player
      %(<div class="doc-player"><p class="doc-player-tag">Player-facing</p>#{html}</div>)
    else
      html
    end
  end

  def render_config(concept, audience:)
    return '' unless concept.config?
    ConfigTables.render(ConfigTables.parse(concept.config_path), audience: audience)
  end

  # Tests are implementer material and never reach a player page.
  def render_tests(concept)
    return '' unless concept.tests?
    DocMarkdown.render(strip_directives(File.read(concept.tests_path, encoding: 'UTF-8')))
  end

  def humanize(name)
    name.split('_').map(&:capitalize).join(' ')
  end
end
