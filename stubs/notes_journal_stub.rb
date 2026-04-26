# notes_journal_stub — campaign log entries grouped by chapter.
# Players see only public entries; DM sees everything plus a
# "DM only" tag on private rows. The stub takes the entry list as
# an argument so callers can pre-filter (e.g. by chapter).

helpers do
  def notes_journal_stub(entries:, dm_view: false, current_chapter: nil,
                         active_only: false, editable: false)
    visible = entries.reject { |e| !dm_view && e['public'] == false }
    visible = visible.reject { |e| e['type'].to_s == 'chapter_title' }
    visible = visible.select { |e| current_chapter.nil? || e['chapter'] == current_chapter }
    visible = visible.select { |e| e['active'] } if active_only
    erb :"stubs/_notes_journal_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      entries: visible,
      dm_view: dm_view,
      editable: editable && dm_view
    }
  end
end

post '/notes/journal/add' do
  halt 403, 'forbidden' unless current_user&.dm?
  NOTES_STATE.add_note(
    chapter:     params[:chapter].to_i,
    note:        params[:note].to_s,
    title:       params[:title].to_s,
    public_flag: params[:public] == '1',
    active:      params[:active] == '1'
  )
  redirect(request.referrer || '/notes')
end

post '/notes/journal/update' do
  halt 403, 'forbidden' unless current_user&.dm?
  fields = {}
  fields['note']    = params[:note]    if params.key?('note')
  fields['title']   = params[:title]   if params.key?('title')
  fields['chapter'] = params[:chapter] if params.key?('chapter')
  fields['public']  = params[:public] == '1'  if params.key?('public_set')
  fields['active']  = params[:active] == '1'  if params.key?('active_set')
  NOTES_STATE.update_note(params[:id].to_i, fields)
  redirect(request.referrer || '/notes')
end

post '/notes/journal/delete' do
  halt 403, 'forbidden' unless current_user&.dm?
  NOTES_STATE.delete_note(params[:id].to_i)
  redirect(request.referrer || '/notes')
end
