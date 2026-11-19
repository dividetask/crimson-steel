require 'monitor'

# "Something changed" notices for the Android app and the DM's Encounter
# page (docs/project/live_updates.md), so they fetch only when there is
# something new instead of asking every second.
#
# Every successful change to the game (any POST that succeeds — the web app
# changes state only through POSTs) moves the version on. A listener holds
# one connection open (Server-Sent Events, GET /api/events or
# /encounter/events) and is woken as soon as the version moves; it then
# fetches what it shows. Each listener holds one web-server thread while it
# is connected, so the server runs with enough threads for a full table
# (8 players and the DM — see THREADS).
class ChangeFeed
  # Web-server threads: a held connection per phone and DM page, plus room
  # for the ordinary requests they make when they fetch.
  THREADS = 32
  # A comment line this often keeps the connection alive (and lets the
  # server notice a listener that went away).
  HEARTBEAT_SECONDS = 20
  # A connection is closed after this long; the listener reconnects at once.
  # Keeps a lost listener from holding a thread for long.
  MAX_SECONDS = 600

  def self.instance = (@instance ||= new)
  def self.instance=(feed)
    @instance = feed
  end

  attr_reader :version

  # Ctrl-C (or TERM) on the server: close every live connection at once, so
  # the web server's graceful stop has nothing left to wait for. Wraps the
  # web server's own handler; call once it has set it (after boot).
  def self.close_on_signals!
    %w[INT TERM].each do |sig|
      previous = Signal.trap(sig) do
        instance.close!
        previous.call if previous.respond_to?(:call)
      end
    end
  end

  def initialize
    @version = 0
    @closing = false
    @lock = Monitor.new
    @moved = @lock.new_cond
  end

  # The server is stopping: end every stream now. Safe from a signal
  # handler (no lock is taken there; the listeners notice within a moment).
  def close!
    @closing = true
    Thread.new { @lock.synchronize { @moved.broadcast } }
  end

  def closing? = @closing

  # Something changed: wake every listener.
  def bump!
    @lock.synchronize do
      @version += 1
      @moved.broadcast
    end
  end

  # Wait until the version moves past +seen+ or +timeout+ seconds pass.
  # Returns the current version.
  def wait_past(seen, timeout)
    @lock.synchronize do
      deadline = Time.now + timeout
      while @version <= seen && !@closing
        left = deadline - Time.now
        break if left <= 0
        @moved.wait([left, 0.5].min) # never long, so a stop is noticed quickly
      end
      @version
    end
  end

  # The Server-Sent Events body: "changed" each time the version moves
  # (several quick changes become one notice), a heartbeat comment between.
  # Ends after +max+ seconds, or when the listener has gone away.
  def stream(out, max: MAX_SECONDS, heartbeat: HEARTBEAT_SECONDS)
    seen = version
    out << "retry: 3000\n"
    out << "event: changed\ndata: {\"v\":#{seen}}\n\n" # connected: fetch once
    started = Time.now
    while Time.now - started < max && !@closing
      now = wait_past(seen, [heartbeat, max - (Time.now - started)].min)
      break if @closing
      if now > seen
        sleep 0.15 # gather a burst of changes into one notice
        seen = version
        out << "event: changed\ndata: {\"v\":#{seen}}\n\n"
      else
        out << ": ping\n\n"
      end
    end
  rescue IOError, Errno::EPIPE, Errno::ECONNRESET
    # The listener went away.
  end
end
