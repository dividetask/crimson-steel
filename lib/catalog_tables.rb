# Renders a piece of rule data — a nested config value or a section of a
# catalog — as an HTML table, for the {{table: …}} directive in the design
# docs (docs/common/file_conventions.md → Tables).
#
# The data's own shape picks the layout:
#
#   { name => { field => … } }   a row per name, a column per field
#   { name => [ … ] }            a row per name and, when the positions are
#                                named with `index`, a column per position
#   { name => value }            two columns: name, value
#   [ { field => … } ]           a row per position, a column per field
#   [ value ]                    two columns: position, value
module CatalogTables
  BLANK = '—'.freeze

  module_function

  # Options, all optional, as written in the directive:
  #   columns  "a, b=Header, c.d" — the fields to show, in order. `=` names
  #            the column; `.` reaches into a nested value (and, through a
  #            list, into each of its entries).
  #   rows     the names to show, in order (an Array).
  #   label    heading of the name column.
  #   value    heading of the value column.
  #   index    heading of the position column, and the prefix of a numbered
  #            column ("Tier" gives "Tier 0", "Tier 1", …).
  #   inherit  the field that names a row's parent. A row then starts from
  #            its parent's values: its own win, numbers inside a nested map
  #            add up, and lists join.
  #
  # Returns nil when the data has no tabular shape.
  def render(data, options = {})
    data = inherited(data, options['inherit']) if options['inherit'] && data.is_a?(Hash)
    data = only_rows(data, options['rows'])    if options['rows'] && data.is_a?(Hash)

    head, body =
      case shape(data, options)
      when :records
        records(data.keys.map { |k| humanize(k) }, data.values, options['label'] || 'Name', options)
      when :record_list
        records(data.each_index.to_a, data, options['index'] || '#', options)
      when :matrix
        matrix(data, options)
      when :pairs
        pairs(data.map { |k, v| [humanize(k), v] }, options['label'] || 'Name', options)
      when :list
        pairs(data.each_with_index.map { |v, i| [i, v] }, options['index'] || '#', options)
      else
        return nil
      end
    html(head, body)
  end

  def shape(data, options = {})
    case data
    when Hash
      return nil if data.empty?
      values = data.values
      if values.any?(Hash) && values.all? { |v| v.nil? || v.is_a?(Hash) }
        :records
      elsif options['index'] && values.all? { |v| v.is_a?(Array) && v.none? { |e| e.is_a?(Hash) || e.is_a?(Array) } }
        :matrix
      else
        :pairs
      end
    when Array
      return nil if data.empty?
      data.all?(Hash) ? :record_list : :list
    end
  end

  def records(names, rows, name_heading, options)
    columns = columns_for(rows, options['columns'])
    head = [name_heading] + columns.map { |field, heading| heading || column_heading(field, options['index']) }
    body = names.zip(rows).map do |name, row|
      [name] + columns.map { |field, _| cell(dig(row, field.to_s.split('.'))) }
    end
    [head, body]
  end

  def matrix(data, options)
    width = data.values.map(&:length).max
    head  = [options['label'] || 'Name'] + (0...width).map { |i| column_heading(i, options['index']) }
    body  = data.map { |name, list| [humanize(name)] + (0...width).map { |i| cell(list[i]) } }
    [head, body]
  end

  def pairs(rows, name_heading, options)
    [[name_heading, options['value'] || 'Value'], rows.map { |name, value| [name, cell(value)] }]
  end

  def columns_for(rows, spec)
    if spec
      spec.split(',').map(&:strip).reject(&:empty?).map { |c| c.split('=', 2).map(&:strip) }
    else
      rows.flat_map { |row| row.is_a?(Hash) ? row.keys : [] }.uniq.map { |field| [field, nil] }
    end
  end

  # A dotted field is headed by the value it reaches into.
  def column_heading(field, index_label)
    numbered = field.is_a?(Integer) || field.to_s.match?(/\A\d+\z/)
    numbered && index_label ? "#{index_label} #{field}" : humanize(field.to_s.split('.').first)
  end

  # Follow a dotted field into a value. A list along the way is followed
  # into each of its entries.
  def dig(value, parts)
    return value if parts.empty?
    case value
    when Hash
      key = parts.first
      key = Integer(key, exception: false) unless value.key?(key)
      value.key?(key) ? dig(value[key], parts.drop(1)) : nil
    when Array
      value.map { |entry| dig(entry, parts) }.compact
    end
  end

  def inherited(data, field)
    data.to_h do |name, row|
      chain = []
      seen  = {}
      at    = name
      while data[at].is_a?(Hash) && !seen[at]
        seen[at] = true
        chain.unshift(data[at])
        at = data[at][field]
      end
      [name, chain.empty? ? row : chain.reduce { |base, own| inherit_into(base, own) }]
    end
  end

  def inherit_into(base, own)
    base.merge(own) do |_field, old, new|
      if old.is_a?(Hash) && new.is_a?(Hash)
        old.merge(new) { |_k, a, b| a.is_a?(Numeric) && b.is_a?(Numeric) ? a + b : b }
      elsif old.is_a?(Array) && new.is_a?(Array)
        (old + new).uniq
      else
        new
      end
    end
  end

  def only_rows(data, names)
    Array(names).each_with_object({}) do |name, kept|
      key = [name, name.to_s, Integer(name.to_s, exception: false)].find { |k| data.key?(k) }
      kept[key] = data[key] unless key.nil?
    end
  end

  def cell(value)
    case value
    when nil   then BLANK
    when true  then 'yes'
    when false then 'no'
    when Hash
      value.empty? ? BLANK : value.map { |k, v| "#{k}: #{nested(v)}" }.join(', ')
    when Array
      return BLANK if value.empty?
      value.map { |v| nested(v) }.join(value.any?(Hash) ? '; ' : ', ')
    else
      text = value.to_s
      text.empty? ? BLANK : text
    end
  end

  # A value inside a cell that is already a list or a map: a different
  # separator, so the reader can tell the levels apart.
  def nested(value)
    case value
    when Hash  then value.map { |k, v| "#{k}: #{nested(v)}" }.join(', ')
    when Array then value.map { |v| nested(v) }.join(' / ')
    else cell(value)
    end
  end

  # snake_case reads as a title; a trailing underscore marks a family
  # (`craft_`). Anything already written for people is left alone.
  def humanize(name)
    text = name.to_s
    return text unless text.match?(/\A[a-z][a-z0-9]*(?:_[a-z0-9]+)*_?\z/)
    words = text.split('_').map(&:capitalize).join(' ')
    text.end_with?('_') ? "#{words} (any)" : words
  end

  def html(head, body)
    out = +'<table class="catalog-table"><thead><tr>'
    head.each { |heading| out << "<th>#{escape(heading)}</th>" }
    out << '</tr></thead><tbody>'
    body.each do |row|
      out << '<tr>'
      row.each_with_index do |text, i|
        out << (i.zero? ? %(<th scope="row">#{escape(text)}</th>) : "<td>#{escape(text)}</td>")
      end
      out << '</tr>'
    end
    out << '</tbody></table>'
  end

  def escape(text)
    text.to_s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
