# notes_combined_stub — single feed of journal notes, characters of
# interest, and images for /notes and /scene. Items are grouped by
# chapter; a chapter divider is emitted whenever the chapter
# changes. Maps are rendered separately by notes_block.
#
# Inputs:
#   notes      — array shaped like NOTES_STATE.effective_notes(...).
#                Mixed types: type:"note" and type:"character".
#                Other types (chapter_title etc.) are dropped.
#   images     — array shaped like NOTES_STATE.effective_images(...).
#   chapters   — DATA.chapters list, used to render chapter titles.
#
# Public/active filtering matches the per-section stubs.

helpers do
  def notes_combined_stub(notes:, images:, chapters: [], dm_view: false,
                          current_chapter: nil, active_only: false,
                          editable_journal: false, editable_images: false)
    items = []

    notes.each do |n|
      type = n['type'].to_s
      next unless type == 'note' || type == 'character'
      next if !dm_view && n['public'] == false
      next if active_only && !n['active']
      next if current_chapter && n['chapter'] != current_chapter
      items << { kind: type, entry: n, chapter: n['chapter'].to_i, sort_id: n['id'].to_i }
    end

    images.each do |i|
      next if !dm_view && i['public'] == false
      next if active_only && !i['active']
      next if current_chapter && i['chapter'] != current_chapter
      items << { kind: 'image', entry: i, chapter: i['chapter'].to_i, sort_id: i['id'].to_i }
    end

    items.sort_by! { |it| [it[:chapter], it[:sort_id]] }

    chapter_titles = chapters.each_with_object({}) { |c, h| h[c['number'].to_i] = c['title'] }

    erb :"stubs/_notes_combined_stub", layout: false, locals: {
      stub_id:          SecureRandom.hex(4),
      items:            items,
      chapter_titles:   chapter_titles,
      dm_view:          dm_view,
      editable_journal: editable_journal && dm_view,
      editable_images:  editable_images && dm_view
    }
  end

  # CSS class describing a character's tier. Tier may be negative
  # (above-tier / unknown) or 0+. Anything outside the known range
  # falls back to a generic class.
  def notes_tier_class(tier)
    return 'notes-tier-unknown' if tier.nil?
    "notes-tier-#{tier.to_i}"
  end

  # First ~140 chars are shown by default; the rest hides behind a
  # <details>/<summary>. Only collapses notes longer than the cutoff
  # so short ones render flat.
  NOTES_BODY_PREVIEW_CHARS = 220

  def notes_body_html(text)
    raw  = text.to_s
    safe = h(raw).gsub("\n", '<br>')
    return %(<div class="notes-body">#{safe}</div>) if raw.length <= NOTES_BODY_PREVIEW_CHARS

    cut = raw[0, NOTES_BODY_PREVIEW_CHARS].rstrip
    preview = h(cut).gsub("\n", '<br>')
    rest    = h(raw[cut.length..]).gsub("\n", '<br>')
    <<~HTML
      <div class="notes-body notes-body-collapsible">
        <span class="notes-body-preview">#{preview}<span class="notes-body-ellipsis">…</span></span>
        <span class="notes-body-rest">#{rest}</span>
        <button type="button" class="notes-body-toggle" data-state="collapsed"
                onclick="this.closest('.notes-body-collapsible').classList.toggle('expanded'); this.dataset.state = this.dataset.state==='collapsed' ? 'expanded' : 'collapsed'; this.textContent = this.dataset.state==='collapsed' ? 'Show more' : 'Show less';">Show more</button>
      </div>
    HTML
  end
end
