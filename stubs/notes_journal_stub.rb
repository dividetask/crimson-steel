# notes_journal_stub — campaign log entries grouped by chapter.
# Players see only public entries; DM sees everything plus a
# "DM only" tag on private rows. The stub takes the entry list as
# an argument so callers can pre-filter (e.g. by chapter).

helpers do
  def notes_journal_stub(entries:, dm_view: false, current_chapter: nil)
    visible = entries.reject { |e| !dm_view && e['public'] == false }
    visible = visible.reject { |e| e['type'].to_s == 'chapter_title' }
    visible = visible.select { |e| current_chapter.nil? || e['chapter'] == current_chapter }
    erb :"stubs/_notes_journal_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      entries: visible,
      dm_view: dm_view
    }
  end
end
