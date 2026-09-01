require 'json'
require 'open3'

module Sessions
  # Ruby side of the scripted-dice bridge. Keeps one long-lived `node`
  # process running dice_bridge.mjs so a Session Test resolves its Rolls
  # through the browser's own Check Resolution / Scoring modules instead
  # of a Ruby re-implementation of them.
  #
  # See docs/project/session_tests.md — "Scripted dice".
  module DiceBridge
    SCRIPT = File.expand_path('dice_bridge.mjs', __dir__).freeze

    class Unavailable < StandardError; end
    class Error < StandardError; end

    module_function

    # True when a `node` capable of running the bridge is on PATH. Session
    # specs skip themselves (rather than fail) when it is missing.
    def available?
      return @available unless @available.nil?
      @available = system('node', '--version', out: File::NULL, err: File::NULL) ? true : false
    end

    # Resolve a set of Rolls against their scripted dice.
    #
    #   rolls  — [{ id:, side:, base_tn:, bonus_penalty_list:, dice_count:,
    #               dice: [...] }, ...]
    #   spread — true for an area (Spread) Check: the caster is compared
    #            against each Opposer independently.
    #
    # Returns { "<id>" => { tn:, starting_value:, dois:, critical_count:,
    #                       outcome:, final_dice: } }.
    def resolve(rolls:, spread: false)
      request = { rolls: rolls.map { |r| stringify(r) }, spread: spread }
      response = exchange(request)
      raise Error, "dice bridge: #{response['error']}" unless response['ok']
      response['rolls'].transform_values { |v| symbolize(v) }
    end

    def exchange(request)
      io = process
      io[:stdin].puts(JSON.generate(request))
      io[:stdin].flush
      line = io[:stdout].gets
      raise Error, 'dice bridge closed unexpectedly' if line.nil?
      JSON.parse(line)
    end

    def process
      @process ||= begin
        raise Unavailable, 'node is required to run the Session Tests' unless available?
        stdin, stdout, stderr, wait = Open3.popen3('node', SCRIPT)
        at_exit { shutdown }
        { stdin: stdin, stdout: stdout, stderr: stderr, wait: wait }
      end
    end

    def shutdown
      return unless defined?(@process) && @process
      @process[:stdin].close rescue nil
      @process[:wait].join   rescue nil
      @process = nil
    end

    def stringify(roll)
      roll.each_with_object({}) { |(k, v), h| h[k.to_s] = v }
    end

    def symbolize(hash)
      hash.each_with_object({}) { |(k, v), h| h[k.to_sym] = v }
    end
  end
end
