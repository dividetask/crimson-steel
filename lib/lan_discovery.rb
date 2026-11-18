require 'socket'
require 'json'

# LAN discovery for the Android app (docs/project/android_app.md → Connecting).
#
# The app does not ask for an IP address. It broadcasts a small UDP probe on
# the Wi-Fi network; this responder answers with the HTTP port, and the app
# uses the reply's source address as the server address.
#
#   probe  (app → broadcast:PORT)  "CRIMSON_STEEL_DISCOVER 1"
#   reply  (server → app)          {"service":"crimson-steel","version":1,
#                                   "http_port":4567,"name":"<campaign>"}
#
# Standard library only. Runs on a background thread so it never blocks the
# web server; any socket error is logged and the thread exits quietly.
module LanDiscovery
  PORT    = 47_567
  PROBE   = 'CRIMSON_STEEL_DISCOVER'.freeze
  SERVICE = 'crimson-steel'.freeze
  VERSION = 1

  module_function

  # The reply to send for a received datagram, or nil to ignore it.
  def reply_for(message, http_port:, name: nil)
    return nil unless message.to_s.strip.start_with?(PROBE)
    JSON.generate(service: SERVICE, version: VERSION, http_port: Integer(http_port), name: name.to_s)
  end

  # Start answering probes on UDP PORT. +name+ may be a Proc so the reply
  # carries the current campaign name. Returns the Thread (nil if the port
  # could not be bound).
  def start(http_port:, name: nil, port: PORT, logger: $stderr)
    socket = UDPSocket.new
    socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_REUSEADDR, true)
    socket.bind('0.0.0.0', port)
    logger&.puts("[discovery] answering Crimson Steel app probes on UDP #{port}")
    Thread.new do
      Thread.current.name = 'lan-discovery' if Thread.current.respond_to?(:name=)
      loop do
        message, from = socket.recvfrom(512)
        current = name.respond_to?(:call) ? (name.call rescue nil) : name
        reply = reply_for(message, http_port: http_port, name: current)
        socket.send(reply, 0, from[3], from[1]) if reply
      rescue IOError, SystemCallError => e
        logger&.puts("[discovery] stopped: #{e.message}")
        break
      end
    end
  rescue SystemCallError => e
    logger&.puts("[discovery] could not listen on UDP #{port}: #{e.message}")
    nil
  end
end
