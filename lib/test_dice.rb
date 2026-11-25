# Test-only scripted dice. Off unless the server starts with
# CRIMSON_TEST_DICE=1 (the scenario runner sets it). While on, every die the
# server or the DM's browser rolls is taken from one FIFO queue of faces;
# once the queue is empty it falls back to real random and counts the roll as
# unscripted so a scenario can fail on dice it did not plan for.
#
# rand(range) takes a face as is. rand(n) (index picks, e.g. a d-n Roll Table
# face or a random pool pick) takes a 1-based face and returns face - 1.
module TestDice
  Entry = Struct.new(:face, :max, :source, :scripted, keyword_init: true)

  class Rng
    def initialize(source) = @source = source

    def rand(arg = nil)
      case arg
      when Range then TestDice.next_face(arg.min, arg.max, @source)
      when Integer then TestDice.next_face(1, arg, @source) - 1
      else Random.rand
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
      @lock.synchronize { @queue.concat(Array(faces).map { Integer(_1) }) }
    end

    def reset!
      @lock.synchronize { @queue.clear; @log.clear }
    end

    def next_face(min, max, source)
      @lock.synchronize do
        face = @queue.first
        scripted = !face.nil?
        if scripted
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

    def status
      @lock.synchronize do
        { queued: @queue.dup, rolled: @log.map(&:to_h), unscripted: @log.count { !_1.scripted } }
      end
    end
  end
end
