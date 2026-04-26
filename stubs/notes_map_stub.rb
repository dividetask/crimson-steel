# notes_map_stub — gallery of map entries. Real binaries are not
# wired up yet; the stub renders an inline SVG placeholder. Players
# see only entries with public => true. When active_only is set,
# only entries flagged active are rendered (this is how /scene
# narrows the full notes list down to the current scene).

helpers do
  def notes_map_stub(entries:, dm_view: false, current_chapter: nil, active_only: false)
    visible = entries.reject { |e| !dm_view && e['public'] == false }
    visible = visible.select { |e| current_chapter.nil? || e['chapter'] == current_chapter }
    visible = visible.select { |e| e['active'] } if active_only
    erb :"stubs/_notes_map_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      entries: visible,
      dm_view: dm_view
    }
  end

  def notes_map_placeholder
    vlines = (1..7).map { |i| %(<line x1="#{i * 50}" y1="0" x2="#{i * 50}" y2="240"/>) }.join
    hlines = (1..4).map { |j| %(<line x1="0" y1="#{j * 48}" x2="400" y2="#{j * 48}"/>) }.join
    <<~SVG
      <svg viewBox="0 0 400 240" preserveAspectRatio="xMidYMid slice"
           xmlns="http://www.w3.org/2000/svg" class="notes-map-svg">
        <rect width="400" height="240" fill="#eef1e8"/>
        <g stroke="#c5cdb4" stroke-width="1">#{vlines}#{hlines}</g>
        <path d="M0,160 Q100,140 200,150 T400,160" stroke="#8aa86b" stroke-width="3" fill="none"/>
        <rect x="180" y="100" width="40" height="24" fill="#9c7a4a" stroke="#5d4520" stroke-width="1"/>
        <text x="200" y="118" text-anchor="middle" fill="#fff"
              font-family="Arial,sans-serif" font-size="11">wagon</text>
        <circle cx="60"  cy="80"  r="6" fill="#577a99"/>
        <circle cx="80"  cy="60"  r="6" fill="#577a99"/>
        <circle cx="320" cy="180" r="6" fill="#a04848"/>
        <circle cx="340" cy="200" r="6" fill="#a04848"/>
        <circle cx="350" cy="170" r="6" fill="#a04848"/>
      </svg>
    SVG
  end
end
