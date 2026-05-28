# Render the canonical test markdown files under docs/common/ as a
# scannable visual stack on the Status page beneath the matching
# stub. Each test paragraph in the markdown ('**Title.** body…')
# becomes a card; dice arrays inside the body render as the same
# colored .die boxes the stubs use; inline `code` and *italics* /
# **bold** get light styling. No markdown gem required — a tiny
# inline parser handles the limited subset the test files use.
#
# Per-test TN context: the parser scans each test for explicit TN
# values ("Clamped to N", "TN = … = N", "TN of N") and uses that to
# color dice ≥ TN as Successes. Tests under a "Resolve a Roll without
# a Target Number" section get no success coloring; everything else
# falls back to the dice-resolution config's Base Target Number.
require 'yaml'

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
    # The 'conditions' test file uses [amount, tick_length] config
    # pairs (e.g. `[1, 7]` for Heal Rate) that the dice regex would
    # otherwise misread as dice rolls. Disable TN-based Success
    # coloring there; 1s still render red, Die Size still renders
    # blue.
    apply_tn = view_key != 'conditions'
    parse_to_html(File.read(path, encoding: 'UTF-8'), apply_tn)
  end

  def title_for(view_key)
    TITLES[view_key]
  end

  def default_tn
    config.base_target_number
  end

  def die_size
    config.die_size
  end

  def config
    @config ||= DiceResolution::Config.load
  end

  # ----- Top-level parse -----

  def parse_to_html(md, apply_tn = true)
    # Skip everything before the first '## ' section heading. The
    # H1 + intro + config bullet list isn't test data.
    lines = md.lines.map(&:rstrip)
    sections = []
    current = nil
    acc = []

    lines.each do |line|
      if line =~ /\A## (.+)\z/
        sections << finalize_section(current, acc, apply_tn) if current
        current = $1
        acc = []
      elsif line == '---'
        # Section separator — flush.
        sections << finalize_section(current, acc, apply_tn) if current
        current = nil
        acc = []
      elsif current
        acc << line
      end
    end
    sections << finalize_section(current, acc, apply_tn) if current

    sections.map { |s| render_section(s) }.join
  end

  def finalize_section(heading, lines, apply_tn)
    no_tn = !apply_tn || heading.to_s.match?(/without\s+a\s+Target\s+Number/i)
    { heading: heading, tests: parse_tests(lines, no_tn) }
  end

  def parse_tests(lines, no_tn_section)
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

    paragraphs.filter_map { |para| parse_test_paragraph(para, no_tn_section) }
  end

  def parse_test_paragraph(para_lines, no_tn_section)
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

    test = { title: title, body: prose.join(' ').strip, bullets: bullets }
    test[:tn] = no_tn_section ? nil : (extract_tn(test) || default_tn)
    test
  end

  # Pull the test's effective TN out of its prose+bullets. Priority:
  # 1. "Clamped to N"            — the final TN after clamping wins.
  # 2. "TN = … = N"              — last number in a TN equation.
  # 3. "TN of N" / "at TN N"     — bare mentions.
  # Returns nil if nothing matches; the caller falls back to default.
  # "TN Net Modifier" doesn't match `TN\s*=` because the words sit
  # between TN and the =, so the two patterns coexist.
  def extract_tn(test)
    text = ([test[:body]] + test[:bullets]).join(' ')

    if (m = text.match(/[Cc]lamped\s+to\s+(\d+)/))
      return m[1].to_i
    end

    if (m = text.match(/(?<![A-Za-z])TN\s*=\s*([^.,]+)/))
      nums = m[1].scan(/\d+/).map(&:to_i)
      return nums.last if nums.any?
    end

    if (m = text.match(/(?:at\s+)?TN\s+(?:of\s+)?(\d+)/))
      return m[1].to_i
    end

    nil
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
    tn = test[:tn]
    out = +'<div class="test-card">'
    out << %(<div class="test-card-title">#{render_inline(test[:title], tn)}</div>)
    unless test[:body].empty?
      out << %(<div class="test-card-body">#{render_inline(test[:body], tn)}</div>)
    end
    if test[:bullets].any?
      out << '<ul class="test-card-bullets">'
      test[:bullets].each { |b| out << %(<li>#{render_inline(b, tn)}</li>) }
      out << '</ul>'
    end
    out << '</div>'
    out
  end

  # ----- Inline transformations -----

  def render_inline(text, tn = nil)
    s = escape(text)
    s = render_dice_arrays(s, tn)
    s = render_code_spans(s)
    s = render_bold(s)
    s = render_italic(s)
    s
  end

  # Catch '[ n, n, n, … ]' (digits 1..Die Size separated by commas)
  # and render the digits as the same colored .die boxes the stubs
  # use. 1s render as Failures, Die Size as Criticals, dice ≥ TN as
  # Successes (when a TN was supplied), everything else as Neutral.
  def render_dice_arrays(s, tn = nil)
    s.gsub(/\[(\s*\d+(?:\s*,\s*\d+)+\s*)\]/) do
      values = Regexp.last_match(1).split(',').map { |v| v.strip.to_i }
      next Regexp.last_match(0) if values.empty? || values.any? { |v| v < 1 || v > die_size }
      pieces = values.map { |v| render_die(v, tn) }
      '[&nbsp;' + pieces.join(', ') + '&nbsp;]'
    end
  end

  def render_die(v, tn = nil)
    cls =
      if v == 1
        'fail'
      elsif v == die_size
        'crit'
      elsif tn && v >= tn
        'success'
      else
        'neutral'
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
