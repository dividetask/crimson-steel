# notes_characters_stub — characters of interest (NPCs the party
# has met or is tracking). Players see only entries with
# public => true; DM sees everything plus a "DM only" tag on
# private rows. Optional chapter filter.

helpers do
  def notes_characters_stub(entries:, dm_view: false, current_chapter: nil)
    visible = entries.reject { |e| !dm_view && e['public'] == false }
    visible = visible.select { |e| current_chapter.nil? || e['chapter'] == current_chapter }
    erb :"stubs/_notes_characters_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      entries: visible,
      dm_view: dm_view
    }
  end
end
