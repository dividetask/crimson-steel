# Render the canonical test markdown files under docs/common/ as a
# scannable visual stack on the Status page beneath the matching
# stub. Each test paragraph in the markdown ('**Title.** body…')
# becomes a card; dice arrays inside the body render as the same
# colored .die boxes the stubs use; inline `code` and *italics* /
# **bold** get light styling. No markdown gem required — a tiny
# inline parser handles the limited subset the test files use.
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
    parse_to_html(File.read(path, encoding: 'UTF-8'))
  end

  def title_for(view_key)
    TITLES[view_key]
  end

  # ----- Top-level parse -----

  def parse_to_html(md)
    # Skip everything before the first '## ' section heading. The
    # H1 + intro + config bullet list isn't test data.
    lines = md.lines.map(&:rstrip)
    sections = []
    current = nil
    acc = []

    lines.each do |line|
      if line =~ /\A## (.+)\z/
        sections << finalize_section(current, acc) if current
        current = $1
        acc = []
      elsif line == '---'
        # Section separator — flush.
        sections << finalize_section(current, acc) if current
        current = nil
        acc = []
      elsif current
        acc << line
      end
    end
    sections << finalize_section(current, acc) if current

    sections.map { |s| render_section(s) }.join
  end

  def finalize_section(heading, lines)
    { heading: heading, tests: parse_tests(lines) }
  end

  def parse_tests(lines)
    # Split into paragraphs separated by blank lines.
    paragraphs = []
    current = []
    lines.each do |line|
      if line.empty?
        paragraphs << current unless current.empty?
        current = []
      else
        current << line
      end
    end
    paragraphs << current unless current.empty?

    paragraphs.filter_map { |para| parse_test_paragraph(para) }
  end

  def parse_test_paragraph(para_lines)
    first = para_lines.first
    m = first.match(/\A\*\*(.+?)\*\*\s*(.*)\z/)
    return nil unless m

    title = m[1]
    head  = m[2]
    rest  = para_lines[1..] || []

    prose = head.empty? ? [] : [head]
    bullets = []
    rest.each do |line|
      if line =~ /\A- (.+)\z/
        bullets << $1
      else
        prose << line
      end
    end

    { title: title, body: prose.join(' ').strip, bullets: bullets }
  end

  # ----- Rendering -----

  def render_section(section)
    out = +'<section class="test-section">'
    out << %(<h3 class="test-section-h">#{escape(section[:heading])}</h3>)
    section[:tests].each { |t| out << render_test(t) }
    out << '</section>'
    out
  end

  def render_test(test)
    out = +'<div class="test-card">'
    out << %(<div class="test-card-title">#{render_inline(test[:title])}</div>)
    unless test[:body].empty?
      out << %(<div class="test-card-body">#{render_inline(test[:body])}</div>)
    end
    if test[:bullets].any?
      out << '<ul class="test-card-bullets">'
      test[:bullets].each { |b| out << %(<li>#{render_inline(b)}</li>) }
      out << '</ul>'
    end
    out << '</div>'
    out
  end

  # ----- Inline transformations -----

  def render_inline(text)
    s = escape(text)
    s = render_dice_arrays(s)
    s = render_code_spans(s)
    s = render_bold(s)
    s = render_italic(s)
    s
  end

  # Catch '[ n, n, n, … ]' (digits 1..10 separated by commas) and
  # render the digits as the same colored .die boxes the stubs use —
  # 1s render in fail-red, 10s in crit-blue, every other value as
  # the plain neutral box. We don't try to color Successes (would
  # require the TN, which we don't know from prose context).
  def render_dice_arrays(s)
    s.gsub(/\[(\s*\d+(?:\s*,\s*\d+)+\s*)\]/) do
      values = Regexp.last_match(1).split(',').map { |v| v.strip.to_i }
      next Regexp.last_match(0) if values.empty? || values.any? { |v| v < 1 || v > 10 }
      pieces = values.map { |v| render_die(v) }
      '[&nbsp;' + pieces.join(', ') + '&nbsp;]'
    end
  end

  def render_die(v)
    cls =
      case v
      when 1  then 'fail'
      when 10 then 'crit'
      else         'neutral'
      end
    %(<span class="die #{cls}">#{v}</span>)
  end

  def render_code_spans(s)
    s.gsub(/`([^`]+)`/) { %(<code>#{Regexp.last_match(1)}</code>) }
  end

  def render_bold(s)
    s.gsub(/\*\*([^*]+)\*\*/) { %(<strong>#{Regexp.last_match(1)}</strong>) }
  end

  def render_italic(s)
    s.gsub(/(?<![*])\*([^*]+)\*(?![*])/) { %(<em>#{Regexp.last_match(1)}</em>) }
  end

  def escape(s)
    s.gsub('&', '&amp;').gsub('<', '&lt;').gsub('>', '&gt;')
  end
end
