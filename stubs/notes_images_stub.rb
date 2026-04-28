# notes_images_stub — gallery of attached images. Entries with a
# `path` are rendered as real <img> tags pointing into the local
# uploads directory; entries without a path fall back to an inline
# SVG placeholder picked by `kind` ("map", "portrait", "document",
# "location", or anything else). Players see only public entries.

require 'fileutils'

# Uploaded image binaries are stored under public/ so Sinatra's
# static handler serves them directly. Allowed extensions are kept
# narrow so the upload form can't drop arbitrary files (no .svg —
# that path bypasses the placeholder system and could carry script
# content).
NOTES_IMAGE_UPLOAD_DIR  = File.join(__dir__, '..', 'public', 'uploads', 'notes_images').freeze
NOTES_IMAGE_PUBLIC_BASE = '/uploads/notes_images'.freeze
NOTES_IMAGE_ALLOWED_EXT = %w[.jpg .jpeg .png .gif .webp].freeze

helpers do
  def notes_images_stub(entries:, dm_view: false, current_chapter: nil,
                        active_only: false, editable: false)
    visible = entries.reject { |e| !dm_view && e['public'] == false }
    visible = visible.select { |e| current_chapter.nil? || e['chapter'] == current_chapter }
    visible = visible.select { |e| e['active'] } if active_only
    erb :"stubs/_notes_images_stub", layout: false, locals: {
      stub_id:         SecureRandom.hex(4),
      entries:         visible,
      dm_view:         dm_view,
      current_chapter: current_chapter,
      editable:        editable && dm_view
    }
  end

  # Inline SVG placeholder for a missing image binary. Picks a
  # different motif per kind so a wall of placeholders is at least
  # visually distinguishable.
  def notes_image_placeholder(kind)
    case kind.to_s
    when 'map'      then notes_image_svg('Map',      '#e8efe5', '#7da37a')
    when 'portrait' then notes_image_svg('Portrait', '#f0e6d8', '#9c7a4a')
    when 'document' then notes_image_svg('Document', '#f3f0e1', '#a89255')
    when 'location' then notes_image_svg('Location', '#dde7ef', '#577a99')
    else                 notes_image_svg('Image',    '#eaeaea', '#888888')
    end
  end

  def notes_image_svg(label, bg, fg)
    <<~SVG
      <svg viewBox="0 0 200 120" preserveAspectRatio="xMidYMid slice"
           xmlns="http://www.w3.org/2000/svg" class="notes-image-svg">
        <rect width="200" height="120" fill="#{bg}"/>
        <line x1="0" y1="0" x2="200" y2="120" stroke="#{fg}" stroke-width="1"/>
        <line x1="200" y1="0" x2="0" y2="120" stroke="#{fg}" stroke-width="1"/>
        <text x="100" y="64" text-anchor="middle" fill="#{fg}"
              font-family="Arial,sans-serif" font-size="14" font-weight="bold">#{label}</text>
      </svg>
    SVG
  end
end

post '/notes/images/add' do
  halt 403, 'forbidden' unless current_user&.dm?

  upload = params[:file]
  halt 400, 'no file uploaded' unless upload.is_a?(Hash) && upload[:tempfile]

  ext = File.extname(upload[:filename].to_s).downcase
  halt 400, "unsupported image type #{ext}" unless NOTES_IMAGE_ALLOWED_EXT.include?(ext)

  FileUtils.mkdir_p(NOTES_IMAGE_UPLOAD_DIR)
  basename = "#{Time.now.to_i}-#{SecureRandom.hex(6)}#{ext}"
  dest     = File.join(NOTES_IMAGE_UPLOAD_DIR, basename)
  File.open(dest, 'wb') { |f| IO.copy_stream(upload[:tempfile], f) }

  NOTES_STATE.add_image(
    chapter:     params[:chapter].to_i,
    kind:        params[:kind].to_s,
    caption:     params[:caption].to_s,
    public_flag: params[:public] == '1',
    active:      params[:active] == '1',
    path:        "#{NOTES_IMAGE_PUBLIC_BASE}/#{basename}"
  )
  redirect(request.referrer || '/notes')
end

post '/notes/images/delete' do
  halt 403, 'forbidden' unless current_user&.dm?
  rec = NOTES_STATE.delete_image(params[:id].to_i)
  if rec && rec['path'].to_s.start_with?("#{NOTES_IMAGE_PUBLIC_BASE}/")
    rel  = rec['path'].sub(%r{\A/}, '')
    file = File.join(settings.public_folder, rel)
    File.delete(file) if File.file?(file)
  end
  redirect(request.referrer || '/notes')
end
