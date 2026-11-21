# The Android app's newest build in this checkout (docs/project/app_updates.md):
# android/versions/vMAJOR.MINOR.apk, committed by the build automation. The
# server offers it to the phones, so a phone's app matches the server it
# talks to — whatever branch the server has checked out and pulled.
require 'shellwords'

module AppRelease
  DIR = File.expand_path('../android/versions', __dir__).freeze
  NAME = /\Av(\d+)\.(\d+)\.apk\z/

  module_function

  # [major, minor] of a version string such as "v0.036", "v0.036 a (cb86)" or "v0.036.apk".
  def parse(v)
    m = v.to_s.match(/v(\d+)\.(\d+)/)
    m && [m[1].to_i, m[2].to_i]
  end

  GRADLE = File.expand_path('../android/app/build.gradle', __dir__).freeze

  # The app version this checkout's code will build as: versionBase in
  # android/app/build.gradle, e.g. "v0.037 b" (CLAUDE.md → Android build
  # versioning). Its number is the APK the next build will make.
  def checkout_version
    File.read(GRADLE, encoding: 'UTF-8')[/versionBase\s*=\s*"([^"]+)"/, 1]
  rescue StandardError
    nil
  end

  # A warning when the app code here is newer than the newest APK — the build
  # automation has not committed it yet (or the build failed), so the phones
  # would be offered the older APK. nil when the APK is there.
  def pending_warning
    code = checkout_version
    want = parse(code)
    rel = latest
    have = rel && parse(rel[:version])
    return nil unless want && (have.nil? || (want <=> have) > 0)
    last_build = `git -C #{File.dirname(DIR).shellescape} log -1 --format=%s --grep="^Build " 2>/dev/null`.strip rescue ''
    lines = ["WARNING: the app in this checkout is #{code}, but the newest APK here is #{rel ? rel[:version] : 'none'}.",
             "  Phones will be offered #{rel ? rel[:version] : 'nothing'} until the build for #{want.then { |a, b| format('v%d.%03d', a, b) }} lands.",
             '  Wait a few minutes, then `git pull` (no restart needed for the APK).']
    lines << "  Last build commit: #{last_build}" unless last_build.empty?
    lines << '  If it says "Build failed", the APK will not come until the code is fixed.' if last_build.include?('failed')
    lines.join("\n")
  end

  # { version: "v0.036", path:, size: } for the newest APK, or nil.
  def latest
    files = Dir.exist?(DIR) ? Dir.children(DIR).grep(NAME) : []
    best = files.max_by { |f| parse(f) }
    return nil unless best
    path = File.join(DIR, best)
    { version: best.delete_suffix('.apk'), path: path, size: File.size(path) }
  end
end
