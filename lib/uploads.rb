require 'fileutils'
require 'digest'

# Image upload storage for Chronicle Entries. The Chronicle design
# stores an opaque string identifier on the Entry's `image` and
# `creature_token` fields; this module accepts an uploaded file,
# writes it under `public/uploads/`, and returns the web-relative
# path to use as the identifier.
module Uploads
  ROOT_DIR    = File.expand_path('../public/uploads', __dir__)
  URL_PREFIX  = '/uploads'
  ALLOWED_EXT = %w[.png .jpg .jpeg .gif .webp .svg].freeze
  MAX_BYTES   = 8 * 1024 * 1024

  module_function

  # Accepts a Rack file upload hash ({ :filename, :tempfile, :type })
  # and returns the URL-relative path of the stored file, e.g.
  # "/uploads/ab12cd...png". Returns nil if the upload is empty.
  def store(upload)
    return nil if upload.nil?
    tempfile = upload[:tempfile] || upload['tempfile']
    return nil if tempfile.nil?

    filename = (upload[:filename] || upload['filename']).to_s
    ext = File.extname(filename).downcase
    raise ArgumentError, "unsupported file type: #{ext.inspect}" unless ALLOWED_EXT.include?(ext)

    bytes = tempfile.size
    raise ArgumentError, "file exceeds maximum size of #{MAX_BYTES} bytes" if bytes > MAX_BYTES

    tempfile.rewind
    digest = Digest::SHA1.hexdigest(tempfile.read)[0, 16]
    tempfile.rewind

    FileUtils.mkdir_p(ROOT_DIR)
    target = "#{digest}#{ext}"
    File.binwrite(File.join(ROOT_DIR, target), tempfile.read)
    "#{URL_PREFIX}/#{target}"
  end

  # Delete a previously-stored upload. Safe to call with nil; safe
  # to call with paths pointing outside the uploads directory (they
  # are ignored).
  def remove(url)
    return unless url.is_a?(String)
    return unless url.start_with?("#{URL_PREFIX}/")
    name = url.sub("#{URL_PREFIX}/", '')
    return if name.include?('/') || name.include?('..')
    path = File.join(ROOT_DIR, name)
    File.delete(path) if File.exist?(path)
  end
end
