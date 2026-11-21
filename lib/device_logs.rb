require 'fileutils'
require 'time'
require 'shellwords'
require 'base64'

# Logs the phones send to the server (docs/project/device_logs.md): the app's
# debug log (Settings → Send log to server) and screenshots taken while the
# app is open. Each upload is saved in device-logs/ at the top of the repo as
#
#   <time>-<who>.log   a header (the device, the app's build and commit, the
#                      server's commit), then the app's log
#   <time>-<who>.png   the screenshot, when the upload is one
#
# The folder belongs to the branch the logs came from: it is emptied when a
# new branch is made and never merged (CLAUDE.md).
module DeviceLogs
  DIR = File.expand_path('../device-logs', __dir__).freeze
  MAX_LOG_BYTES = 2_000_000
  MAX_PNG_BYTES = 12_000_000
  PNG_MAGIC = "\x89PNG\r\n\x1a\n".b

  module_function

  # The server's checkout: "abc1234 (claude/x)", worked out once.
  def server_commit
    @server_commit ||= begin
      root = File.expand_path('..', __dir__)
      sha = `git -C #{root.shellescape} rev-parse --short=7 HEAD 2>/dev/null`.strip
      branch = `git -C #{root.shellescape} rev-parse --abbrev-ref HEAD 2>/dev/null`.strip
      dirty = `git -C #{root.shellescape} status --porcelain --untracked-files=no 2>/dev/null`.strip.empty? ? '' : ', with local changes'
      sha.empty? ? 'unknown' : "#{sha} (#{branch}#{dirty})"
    rescue StandardError
      'unknown'
    end
  end

  # A file-name-safe word.
  def slug(s)
    w = s.to_s.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|-\z/, '')
    w.empty? ? 'device' : w[0, 40]
  end

  # The header at the top of each .log: +info+ is a Hash of label => value.
  def header(info)
    width = info.keys.map { |k| k.to_s.length }.max.to_i
    lines = info.map { |k, v| "#{k.to_s.ljust(width)} : #{v}" }
    (['=' * 60, *lines, '=' * 60, '']).join("\n")
  end

  # Save one upload. +info+ the header Hash, +log+ the app's log text,
  # +png+ the screenshot's bytes (or nil). Returns the file names saved.
  def save!(who:, info:, log:, png: nil, now: Time.now)
    FileUtils.mkdir_p(DIR)
    base = "#{now.strftime('%Y%m%d-%H%M%S')}-#{slug(who)}"
    base += "-#{rand(1000)}" while File.exist?(File.join(DIR, "#{base}.log"))
    saved = []
    if png
      File.binwrite(File.join(DIR, "#{base}.png"), png)
      saved << "#{base}.png"
      info = info.merge('Screenshot' => "#{base}.png")
    end
    body = log.to_s
    body = body.byteslice(-MAX_LOG_BYTES, MAX_LOG_BYTES).scrub if body.bytesize > MAX_LOG_BYTES
    File.write(File.join(DIR, "#{base}.log"), header(info) + body + (body.end_with?("\n") ? '' : "\n"))
    saved.unshift("#{base}.log")
  end

  def png?(bytes) = bytes.to_s.b.start_with?(PNG_MAGIC)
end
