require_relative 'harness'

module Scenarios
  class StepFailed < StandardError; end

  # A scenario is a list of steps run in order; the first failing step stops
  # it, since later steps build on earlier ones.
  #
  #   Scenarios.define 'simple combat' do
  #     step 'everyone connects' do
  #       party.each_value(&:hello)
  #       check party.size == 4, 'four tablets'
  #     end
  #     step 'DM starts combat', browser: true do ... end
  #   end
  class Definition
    attr_reader :name, :steps, :options, :helper_module

    def initialize(name, **options, &block)
      @name, @options, @steps, @before = name, options, [], {}
      @helper_module = Module.new
      instance_eval(&block)
      missing = @before.keys - @steps.map { _1[:title] }
      raise ArgumentError, "before_step for unknown steps: #{missing.inspect}" unless missing.empty?
      @steps.each { |s| s[:before] = @before[s[:title]] }
    end

    # browser: true marks DM clicks. fast: is the same step by route, used on
    # the fast track (no browser); without it the step is skipped there.
    # blocking: false lets the later steps run when this one fails (a check
    # that nothing after it depends on); the scenario still fails.
    # Methods the steps can call (they run in the step's context).
    def helpers(&block) = @helper_module.module_eval(&block)

    # Runs before the named step on both tracks, e.g. queuing the dice it rolls.
    def before_step(title, &block) = @before[title] = block

    def step(title, browser: false, fast: nil, blocking: true, &block)
      @steps << { title: title, browser: browser, fast: fast, blocking: blocking, block: block }
    end
  end

  REGISTRY = {}

  def self.define(name, **options, &block) = REGISTRY[name] = Definition.new(name, **options, &block)

  # What a step's block sees.
  class Context
    PARTY = ['Ash Windmere', 'Lira Duskmoor', 'Thora Stoneveil', 'Garroth Vask'].freeze
    # Character ids in the example campaign data (docs/common/creatures).
    IDS = { 'Ash' => 1, 'Lira' => 3, 'Thora' => 7, 'Garroth' => 8 }.freeze

    attr_reader :dm, :party, :memo

    def initialize(dm:, tablet_factory:, browser_available:)
      @dm = dm
      @party = PARTY.to_h { |n| [n.split.first, Tablet.new(n, tablet_factory)] }
      @browser_available = browser_available
      @memo = {}
    end

    def browser_available? = @browser_available
    def ids = IDS

    def check(cond, message)
      raise StepFailed, message unless cond
    end

    def expect_eq(actual, expected, what)
      check actual == expected, "#{what}: expected #{expected.inspect}, got #{actual.inspect}"
    end

    def check_ok(response, what)
      check response.ok?, "#{what}: HTTP #{response.status} #{response.body.to_s[0, 300]}"
      response
    end

    # No die should have come from real random.
    def check_dice_scripted
      s = dm.dice_status
      check s['unscripted'].to_i.zero?, "#{s['unscripted']} die/dice rolled without a scripted face: " \
                                        "#{s['rolled'].reject { _1['scripted'] }.inspect}"
    end
  end

  Result = Struct.new(:title, :status, :message)

  def self.run(definition, context)
    context.extend(definition.helper_module)
    results = []
    failed = false
    limit = ENV['SCENARIO_UNTIL'].to_s.empty? ? nil : Integer(ENV['SCENARIO_UNTIL'])
    (limit ? definition.steps.first(limit) : definition.steps).each do |s|
      if failed
        results << Result.new(s[:title], :not_run, nil)
      elsif s[:browser] && !context.browser_available? && !s[:fast]
        results << Result.new(s[:title], :skipped, 'needs the browser')
      else
        begin
          body = s[:browser] && !context.browser_available? ? s[:fast] : s[:block]
          context.instance_exec(&s[:before]) if s[:before]
          context.instance_exec(&body)
          results << Result.new(s[:title], :pass, nil)
        rescue StepFailed, StandardError => e
          failed = true if s[:blocking]
          msg = e.is_a?(StepFailed) ? e.message : "#{e.class}: #{e.message}\n    #{e.backtrace.first(3).join("\n    ")}"
          results << Result.new(s[:title], :fail, msg)
        end
      end
    end
    results
  end

  def self.report(definition, results, io: $stdout)
    io.puts "\n== #{definition.name}"
    results.each_with_index do |r, i|
      tag = { pass: 'PASS', fail: 'FAIL', skipped: 'SKIP', not_run: '----' }[r.status]
      io.puts format('  %-4s %2d. %s', tag, i + 1, r.title)
      io.puts "         #{r.message}" if r.message && r.status == :fail
    end
    results.none? { _1.status == :fail }
  end
end
