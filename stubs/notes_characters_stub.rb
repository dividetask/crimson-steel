# notes_characters_stub — characters of interest. Source rows are
# the type:"character" entries in NOTES_STATE.effective_notes — same
# schema as journal notes, plus an optional `tier` field used to
# colour the name. Players see only entries with public => true; the
# DM sees everything plus a "DM only" tag on private rows.

helpers do
  def notes_characters_stub(entries:, dm_view: false, current_chapter: nil, active_only: false)
    visible = entries.select { |e| e['type'].to_s == 'character' }
    visible = visible.reject { |e| !dm_view && e['public'] == false }
    visible = visible.select { |e| current_chapter.nil? || e['chapter'] == current_chapter }
    visible = visible.select { |e| e['active'] } if active_only
    erb :"stubs/_notes_characters_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      entries: visible,
      dm_view: dm_view
    }
  end
end
