require 'yaml'

# Renders a domain's `*_config.yaml` as a table on the Compendium concept
# page. Values come from YAML; the *descriptions* come from the comments
# the file already carries, so the table reads exactly like the file.
#
# The file conventions (see docs/common/file_conventions.md):
#
#   # ---- Section Name ----     a section divider -> a table sub-heading
#   # Free prose describing the  the contiguous comment block IMMEDIATELY
#   # key(s) below.              above a key describes it — and every key
#                                in the unbroken run that follows it
#   # @dm                        marks the key DM-only (config defaults to
#   Some Key: 8                  player-visible; @dm is the exception)
#
# A comment block separated from the next key by a blank line is preamble
# (a file header, a section note) and belongs to no key.
module ConfigTables
  Row     = Struct.new(:key, :value, :description, :dm_only, keyword_init: true)
  Section = Struct.new(:title, :rows, keyword_init: true)

  SECTION_RE = /\A#\s*-{2,}\s*(.+?)\s*-{2,}\s*\z/
  COMMENT_RE = /\A#\s?(.*)\z/
  KEY_RE     = /\A([A-Za-z][^:]*):\s*(.*)\z/

  module_function

  # Parse a config file into [Section]. Keys declared before any section
  # divider land in a leading untitled Section.
  def parse(path)
    return [] unless path && File.exist?(path)

    text   = File.read(path, encoding: 'UTF-8')
    values = load_values(text)

    sections  = [Section.new(title: nil, rows: [])]
    comments  = []
    dm_only   = false
    after_key = false

    text.each_line do |raw|
      line = raw.chomp

      if (m = line.match(SECTION_RE))
        sections << Section.new(title: m[1], rows: [])
        comments  = []
        dm_only   = false
        after_key = false
      elsif line.strip.empty?
        # A blank line breaks the comment block away from whatever key
        # follows it — that prose was preamble, not a description.
        comments  = []
        dm_only   = false
        after_key = false
      elsif (m = line.match(COMMENT_RE))
        # A comment block that starts after a key begins a fresh
        # description rather than extending the previous one.
        if after_key
          comments  = []
          dm_only   = false
          after_key = false
        end
        body = m[1].strip
        if body == '@dm'
          dm_only = true
        else
          comments << body
        end
      elsif (m = line.match(KEY_RE))
        key = m[1].strip
        if values.key?(key)
          sections.last.rows << Row.new(
            key:         key,
            value:       values[key],
            description: comments.reject(&:empty?).join(' '),
            dm_only:     dm_only
          )
        end
        after_key = true
      end
    end

    sections.reject { |s| s.rows.empty? }
  end

  # Flat { 'Key' => value } for every key in the file — used by the
  # {{Key}} substitution in the design docs.
  def values_for(path)
    return {} unless path && File.exist?(path)
    load_values(File.read(path, encoding: 'UTF-8'))
  end

  def load_values(text)
    parsed = YAML.safe_load(text, aliases: true)
    parsed.is_a?(Hash) ? parsed : {}
  rescue Psych::Exception
    {}
  end

  # Render the sections as HTML. `audience` is :dm or :player; a player
  # never sees a row marked @dm. Returns '' when nothing is visible.
  def render(sections, audience:)
    visible = sections.map do |section|
      rows = section.rows.reject { |r| audience == :player && r.dm_only }
      rows.empty? ? nil : [section, rows]
    end.compact
    return '' if visible.empty?

    out = +''
    visible.each do |section, rows|
      out << %(<h3 class="config-section">#{escape(section.title)}</h3>) if section.title
      out << '<table class="config-table">'
      out << '<thead><tr><th>Setting</th><th>Value</th><th>Description</th></tr></thead><tbody>'
      rows.each do |row|
        classes = row.dm_only ? ' class="config-dm-only"' : ''
        badge   = row.dm_only ? ' <span class="config-badge">DM</span>' : ''
        out << %(<tr#{classes}>)
        out << %(<th scope="row"><code>#{escape(row.key)}</code>#{badge}</th>)
        out << %(<td class="config-value">#{format_value(row.value)}</td>)
        out << %(<td>#{escape(row.description)}</td>)
        out << '</tr>'
      end
      out << '</tbody></table>'
    end
    out
  end

  # Scalars and flat lists read as plain text; anything deeper keeps its
  # YAML shape so a nested catalog is still legible in the cell.
  def format_value(value)
    case value
    when nil            then '<em>null</em>'
    when true, false    then %(<code>#{value}</code>)
    when Numeric        then %(<code>#{value}</code>)
    when String         then %(<code>#{escape(value)}</code>)
    when Array
      if value.all? { |v| v.is_a?(Numeric) || v.is_a?(String) || v == true || v == false }
        %(<code>#{escape(value.join(', '))}</code>)
      else
        %(<pre class="config-nested">#{escape(value.to_yaml.sub(/\A---\n/, ''))}</pre>)
      end
    else
      %(<pre class="config-nested">#{escape(value.to_yaml.sub(/\A---\n/, ''))}</pre>)
    end
  end

  def escape(s)
    s.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
