# Mutable shared state for editable notes. Mirrors SceneState — an
# in-memory overlay on top of the immutable DummyData.notes list. The
# DM can add new notes, edit existing ones (whether they came from
# DummyData or were added later), and delete any note. Players never
# write to this; the route handlers enforce that.
#
# Resets on server restart, same caveat as SceneState. When we wire a
# real backend the on-disk shape lives in something like
# data/notes.json and DummyData.notes goes away.

class NotesState
  def initialize
    @additions = []        # array of newly-created notes
    @overrides = {}        # id => merged-fields hash
    @deletions = []        # array of ids to hide from DummyData
  end

  # Build the effective list: base entries minus anything deleted,
  # with overrides applied, plus any DM-added notes appended.
  def effective_notes(base)
    visible = base.reject { |n| @deletions.include?(n['id']) }
    visible = visible.map { |n| @overrides[n['id']] ? n.merge(@overrides[n['id']]) : n }
    visible + @additions.map { |n| @overrides[n['id']] ? n.merge(@overrides[n['id']]) : n }
  end

  def add_note(chapter:, note:, public_flag:, active: false, owner_id: 0, title: nil)
    rec = {
      'id'       => next_id,
      'owner_id' => owner_id.to_i,
      'chapter'  => chapter.to_i,
      'note'     => note.to_s,
      'public'   => public_flag ? true : false,
      'active'   => active ? true : false
    }
    rec['title'] = title.to_s unless title.to_s.empty?
    @additions << rec
    rec
  end

  def update_note(id, fields)
    id = id.to_i
    cleaned = {}
    cleaned['note']    = fields['note'].to_s    if fields.key?('note')
    cleaned['title']   = fields['title'].to_s   if fields.key?('title')
    cleaned['chapter'] = fields['chapter'].to_i if fields.key?('chapter')
    cleaned['public']  = fields['public']  ? true : false if fields.key?('public')
    cleaned['active']  = fields['active']  ? true : false if fields.key?('active')
    return false if cleaned.empty?
    @overrides[id] = (@overrides[id] || {}).merge(cleaned)
    true
  end

  def delete_note(id)
    @deletions << id.to_i
    @overrides.delete(id.to_i)
    @additions.reject! { |n| n['id'] == id.to_i }
    true
  end

  private

  # Fresh ids start above any DummyData id. 1000 is well clear of the
  # current placeholder numbering.
  def next_id
    base = 1000
    used = @additions.map { |n| n['id'].to_i }
    (used.max || base - 1) + 1
  end
end
