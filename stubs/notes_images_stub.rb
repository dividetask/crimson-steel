# notes_images_stub — gallery of attached images. Real binaries are
# not wired up yet; the stub renders an inline SVG placeholder whose
# look is picked by the entry's `kind` ("map", "portrait",
# "document", "location", or anything else). Players see only public
# entries.

helpers do
  def notes_images_stub(entries:, dm_view: false, current_chapter: nil, active_only: false)
    visible = entries.reject { |e| !dm_view && e['public'] == false }
    visible = visible.select { |e| current_chapter.nil? || e['chapter'] == current_chapter }
    visible = visible.select { |e| e['active'] } if active_only
    erb :"stubs/_notes_images_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      entries: visible,
      dm_view: dm_view
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
