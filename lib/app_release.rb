# The Android app's newest build in this checkout (docs/project/app_updates.md):
# android/versions/vMAJOR.MINOR.apk, committed by the build automation. The
# server offers it to the phones, so a phone's app matches the server it
# talks to — whatever branch the server has checked out and pulled.
module AppRelease
  DIR = File.expand_path('../android/versions', __dir__).freeze
  NAME = /\Av(\d+)\.(\d+)\.apk\z/

  module_function

  # [major, minor] of a version string such as "v0.036", "v0.036 a (cb86)" or "v0.036.apk".
  def parse(v)
    m = v.to_s.match(/v(\d+)\.(\d+)/)
    m && [m[1].to_i, m[2].to_i]
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
