require 'fileutils'

module Sessions
  # The human-readable record of a Session Test.
  #
  # Session Tests assert with ordinary expectations; the transcript is not
  # diffed and never fails a run. It exists so a DM can read what the
  # scenario actually did — every action, every rolled die, every
  # resulting Success — and check the run against the rules by eye.
  # Written to `tmp/session_transcripts/<scenario>.txt` after each
  # example.
  class Transcript
    OUTPUT_DIR = File.expand_path('../../../tmp/session_transcripts', __dir__).freeze

    # `title` is the example's full description; `group` the scenario file's
    # top-level description, which becomes the directory the transcript
    # lands in.
    def initialize(title, group: nil)
      @title = title
      @group = group || title
      @lines = []
    end

    # A new beat of the session ("Round 2", "Day 3 — the marsh road").
    def scene(label)
      @lines << ''
      @lines << "── #{label} #{'─' * [0, 58 - label.length].max}"
      self
    end

    def say(text)
      @lines << text
      self
    end

    # One action with its dice. `rolls` is { label => { dice:, tn:, dois: } }.
    def action(summary, rolls: {}, outcome: nil)
      @lines << "• #{summary}"
      rolls.each do |label, r|
        dice = Array(r[:final_dice] || r[:dice]).join(', ')
        @lines << "    #{label}: [#{dice}] @ TN #{r[:tn]} → #{r[:dois]} successes" \
                  "#{r[:critical_count].to_i.positive? ? " (#{r[:critical_count]} crit)" : ''}"
      end
      @lines << "    → #{outcome}" if outcome
      self
    end

    def to_s
      (["# #{@title}"] + @lines).join("\n") + "\n"
    end

    def write!
      dir = File.join(OUTPUT_DIR, slug(@group))
      FileUtils.mkdir_p(dir)
      # The example's full description opens with the scenario name, which
      # is already the directory — drop it from the file name.
      name = @title.to_s.delete_prefix(@group.to_s).strip
      File.write(File.join(dir, "#{slug(name.empty? ? @title : name)}.txt"), to_s)
    end

    def slug(text)
      text.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')[0, 120]
    end
  end
end
