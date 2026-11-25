# Test-only scripted dice. Off unless the server starts with
# CRIMSON_TEST_DICE=1 (the scenario runner sets it). While on, every die the
# server or the DM's browser rolls is taken from one FIFO queue of faces;
# once the queue is empty it falls back to real random and counts the roll as
# unscripted so a scenario can fail on dice it did not plan for.
#
# rand(range) takes a face as is. rand(n) (index picks, e.g. a d-n Roll Table
# face or a random pool pick) takes a 1-based face and returns face - 1.
# rand() (a chance draw, e.g. a Loot Table row) takes a decimal in [0, 1).
# Whole numbers and decimals are not interchangeable, so a script that has
# drifted out of step with the rolls fails instead of passing by luck.
module TestDice
  Entry = Struct.new(:face, :max, :source, :scripted, keyword_init: true)

  class Rng
    def initialize(source) = @source = source

    def rand(arg = nil)
      case arg
      when Range then TestDice.next_face(arg.min, arg.max, @source)
      when Integer then TestDice.next_face(1, arg, @source) - 1
      else TestDice.next_chance(@source)
      end
    end
  end

  @lock = Mutex.new
  @queue = []
  @log = []

  class << self
    def enabled? = ENV['CRIMSON_TEST_DICE'] == '1'

    def rng(source = 'server') = enabled? ? Rng.new(source) : Random.new

    def push(faces)
      values = Array(faces).map do |v|
        raise ArgumentError, "not a die face or chance: #{v.inspect}" unless v.is_a?(Numeric)
        v.is_a?(Float) ? v : Integer(v)
      end
      @lock.synchronize { @queue.concat(values) }
    end

    def reset!
      @lock.synchronize { @queue.clear; @log.clear }
    end

    def next_face(min, max, source)
      @lock.synchronize do
        face = @queue.first
        scripted = !face.nil?
        if scripted
          raise ArgumentError, "expected a die (#{min}..#{max}, #{source}), next scripted value is #{face}" if face.is_a?(Float)
          unless face.between?(min, max)
            raise ArgumentError, "scripted die #{face} is outside #{min}..#{max} (#{source})"
          end
          @queue.shift
        else
          face = Random.rand(min..max)
        end
        @log << Entry.new(face: face, max: max, source: source, scripted: scripted)
        face
      end
    end

    def next_chance(source)
      @lock.synchronize do
        v = @queue.first
        scripted = !v.nil?
        if scripted
          raise ArgumentError, "expected a chance in [0, 1) (#{source}), next scripted value is #{v}" unless v.is_a?(Float) && v >= 0 && v < 1
          @queue.shift
        else
          v = Random.rand
        end
        @log << Entry.new(face: v, max: nil, source: source, scripted: scripted)
        v
      end
    end

    def status
      @lock.synchronize do
        { queued: @queue.dup, rolled: @log.map(&:to_h), unscripted: @log.count { !_1.scripted } }
      end
    end
  end
end
