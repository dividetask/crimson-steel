require 'tmpdir'
require 'chronicle'

RSpec.describe Chronicle::Store do
  let(:tmp) { Dir.mktmpdir }
  after { FileUtils.remove_entry(tmp) }

  def baseline
    Chronicle::Store.new(
      {
        'campaign_name'   => 'Test Campaign',
        'timestamp'       => { 'day_index' => 100, 'round_of_day' => 600 },
        'current_chapter' => 1,
        'chapters'        => [
          { 'number' => 1, 'name' => 'A' },
          { 'number' => 2, 'name' => 'B' }
        ],
        'entries'         => [],
        'next_id'         => 1
      },
      data_path: File.join(tmp, 'chronicle_data.json')
    )
  end

  def note_payload(**overrides)
    {
      entry_type:         'note',
      chapter:            1,
      title:              'A note',
      public_description: 'body',
      dm_description:     '',
      image:              nil,
      shared:             true,
      hidden_from:        [],
      owner_id:           nil,
      active:             true
    }.merge(overrides)
  end

  def creature_payload(**overrides)
    note_payload(entry_type: 'creature', creature_id: 1001, creature_token: nil, tier: nil).merge(overrides)
  end

  # ---------- Campaign metadata ----------

  describe 'campaign metadata' do
    it 'returns the stored Campaign Name' do
      store = baseline
      store.campaign_name = 'The Long Road'
      expect(store.campaign_name).to eq('The Long Road')
    end

    it 'replaces the Campaign Name' do
      store = baseline
      store.campaign_name = 'A New Beginning'
      expect(store.campaign_name).to eq('A New Beginning')
    end

    it 'returns the stored Timestamp' do
      expect(baseline.timestamp).to eq(day_index: 100, round_of_day: 600)
    end
  end

  # ---------- Advance time ----------

  describe '#advance_time' do
    it 'adds Rounds within a Day' do
      store = baseline
      store.advance_time(rounds: 600 - 600)
      store.advance_time(rounds: 600)
      expect(store.timestamp[:round_of_day]).to eq(1200)
    end

    it 'rolls Rounds into the next Day' do
      store = baseline
      store.advance_time(rounds: 14000 - 600)
      store.advance_time(rounds: 1000)
      expect(store.timestamp).to eq(day_index: 101, round_of_day: 600)
    end

    it 'adds Days only, leaving round_of_day untouched' do
      store = baseline
      store.advance_time(days: 3)
      expect(store.timestamp).to eq(day_index: 103, round_of_day: 600)
    end

    it 'rolls Rounds backwards across a Day boundary' do
      store = baseline
      store.advance_time(rounds: -600)
      store.advance_time(rounds: -1)
      expect(store.timestamp).to eq(day_index: 99, round_of_day: 14399)
    end
  end

  # ---------- Chapters ----------

  describe 'chapters' do
    it 'lists Chapters in number order' do
      store = baseline
      store.add_chapter(number: 0, name: 'Prologue')
      expect(store.list_chapters.map { |c| c[:number] }).to eq([0, 1, 2])
    end

    it 'adds a Chapter' do
      store = baseline
      store.add_chapter(number: 3, name: 'C')
      expect(store.list_chapters.last).to eq(number: 3, name: 'C')
    end

    it 'renames a Chapter' do
      store = baseline
      store.rename_chapter(1, 'Beginnings')
      expect(store.list_chapters.find { |c| c[:number] == 1 }[:name]).to eq('Beginnings')
    end

    it 'removes a Chapter without deleting its Entries' do
      store = baseline
      store.add_entry(note_payload(chapter: 1))
      store.add_entry(note_payload(chapter: 1, title: 'Second'))
      store.remove_chapter(1)
      expect(store.list_chapters.map { |c| c[:number] }).to eq([2])
      expect(store.list_entries(chapter: 1).size).to eq(2)
    end
  end

  # ---------- Entries ----------

  describe 'entries' do
    it 'assigns increasing IDs on add' do
      store = baseline
      a = store.add_entry(note_payload(title: 'A'))
      b = store.add_entry(note_payload(title: 'B'))
      expect(b).to be > a
    end

    it 'edits only the supplied fields' do
      store = baseline
      id = store.add_entry(note_payload(title: 'Old', public_description: 'Original body'))
      store.edit_entry(id, title: 'New')
      e = store.get_entry(id)
      expect(e['title']).to eq('New')
      expect(e['public_description']).to eq('Original body')
    end

    it 'deletes by ID' do
      store = baseline
      id = store.add_entry(note_payload)
      store.delete_entry(id)
      expect(store.get_entry(id)).to be_nil
    end

    it 'returns full record on get for a Creature Reference' do
      store = baseline
      id = store.add_entry(creature_payload(creature_id: 1003, tier: 4))
      e = store.get_entry(id)
      %w[creature_id creature_token tier].each { |f| expect(e).to have_key(f) }
      expect(e['tier']).to eq(4)
    end

    it 'leaves a null tier on a Creature Reference for caller resolution' do
      store = baseline
      id = store.add_entry(creature_payload(tier: nil))
      expect(store.get_entry(id)['tier']).to be_nil
    end

    it 'stores a blank Creature Reference title verbatim' do
      store = baseline
      id = store.add_entry(creature_payload(title: ''))
      expect(store.get_entry(id)['title']).to eq('')
    end

    it 'stores a suffix title on a Creature Reference verbatim' do
      store = baseline
      id = store.add_entry(creature_payload(title: 'the Younger'))
      expect(store.get_entry(id)['title']).to eq('the Younger')
    end

    it 'does not reuse a freed ID after delete' do
      store = baseline
      a = store.add_entry(note_payload)
      store.delete_entry(a)
      b = store.add_entry(note_payload)
      expect(b).to be > a
    end
  end

  describe '#list_entries' do
    let(:store) do
      s = baseline
      s.add_entry(note_payload(chapter: 1, title: 'N1', active: true))
      s.add_entry(note_payload(chapter: 2, title: 'N2', active: false))
      s.add_entry(creature_payload(chapter: 1, title: '', creature_id: 1001))
      s
    end

    it 'returns everything with no filters' do
      expect(store.list_entries.size).to eq(3)
    end

    it 'filters by chapter' do
      expect(store.list_entries(chapter: 1).size).to eq(2)
    end

    it 'filters by entry_type' do
      expect(store.list_entries(entry_type: 'note').size).to eq(2)
    end

    it 'filters by active' do
      expect(store.list_entries(active_only: true).size).to eq(2)
    end

    it 'combines filters conjunctively' do
      expect(store.list_entries(chapter: 1, entry_type: 'note', active_only: true).size).to eq(1)
    end
  end

  describe 'visibility' do
    it 'honors the Shared flag for visible_to filter' do
      store = baseline
      store.add_entry(note_payload(shared: true,  title: 'Public'))
      store.add_entry(note_payload(shared: false, title: 'Private'))
      visible = store.list_entries(visible_to: 7).map { |e| e['title'] }
      expect(visible).to eq(['Public'])
    end

    it 'honors hidden_from even when Shared' do
      store = baseline
      store.add_entry(note_payload(shared: true, hidden_from: [42]))
      expect(store.list_entries(visible_to: 42)).to be_empty
    end

    it 'honors owner_id on an unshared Entry' do
      store = baseline
      store.add_entry(note_payload(shared: false, owner_id: 7))
      expect(store.list_entries(visible_to: 7).size).to eq(1)
      expect(store.list_entries(visible_to: 8)).to be_empty
    end
  end

  describe 'position management' do
    it 'shifts other notes_positions on Set Notes Position' do
      store = baseline
      a = store.add_entry(note_payload(chapter: 1, title: 'A'))
      b = store.add_entry(note_payload(chapter: 1, title: 'B'))
      c = store.add_entry(note_payload(chapter: 1, title: 'C'))
      store.set_notes_position(c, 1)
      positions = [a, b, c].map { |id| [store.get_entry(id)['title'], store.get_entry(id)['notes_position']] }
      expect(positions).to contain_exactly(['A', 2], ['B', 3], ['C', 1])
    end

    it 'scopes notes-position shifts to the Chapter' do
      store = baseline
      a = store.add_entry(note_payload(chapter: 1, title: 'A'))
      d = store.add_entry(note_payload(chapter: 2, title: 'D'))
      e = store.add_entry(note_payload(chapter: 2, title: 'E'))
      store.set_notes_position(e, 1)
      expect(store.get_entry(a)['notes_position']).to eq(1)
      expect(store.get_entry(d)['notes_position']).to eq(2)
      expect(store.get_entry(e)['notes_position']).to eq(1)
    end

    it 'scopes scene-position shifts across all Active Entries' do
      store = baseline
      a = store.add_entry(note_payload(chapter: 1, active: true))
      b = store.add_entry(note_payload(chapter: 2, active: true))
      store.set_scene_position(b, 1)
      expect(store.get_entry(a)['scene_position']).to eq(2)
      expect(store.get_entry(b)['scene_position']).to eq(1)
    end
  end

  describe 'edge cases' do
    it 'permits adding an Entry to a non-existent Chapter' do
      store = baseline
      id = store.add_entry(note_payload(chapter: 99))
      expect(store.list_entries(chapter: 99).map { |e| e['id'] }).to include(id)
      expect(store.list_chapters.map { |c| c[:number] }).not_to include(99)
    end

    it 'treats a missing hidden_from as empty' do
      store = baseline
      id = store.add_entry(note_payload.tap { |p| p.delete(:hidden_from) })
      expect(store.get_entry(id)['hidden_from']).to eq([])
    end

    it 'backfills missing notes_position on load' do
      store = Chronicle::Store.new(
        {
          'campaign_name' => 'T',
          'timestamp' => { 'day_index' => 0, 'round_of_day' => 0 },
          'current_chapter' => 1,
          'chapters' => [{ 'number' => 1, 'name' => 'A' }],
          'entries' => [
            { 'id' => 1, 'entry_type' => 'note', 'chapter' => 1, 'title' => 'X',
              'public_description' => '', 'dm_description' => '', 'image' => nil,
              'shared' => true, 'hidden_from' => [], 'owner_id' => nil, 'active' => false,
              'notes_position' => nil, 'scene_position' => nil }
          ],
          'next_id' => 2
        },
        data_path: File.join(tmp, 'chronicle_data.json')
      )
      expect(store.get_entry(1)['notes_position']).to eq(1)
    end
  end

  describe 'persistence' do
    it 'writes to the data path on mutation' do
      data_path = File.join(tmp, 'chronicle_data.json')
      store = Chronicle::Store.new(
        { 'campaign_name' => 'T', 'timestamp' => { 'day_index' => 0, 'round_of_day' => 0 },
          'current_chapter' => 1, 'chapters' => [], 'entries' => [], 'next_id' => 1 },
        data_path: data_path
      )
      store.add_entry(note_payload)
      reloaded = JSON.parse(File.read(data_path))
      expect(reloaded['entries'].size).to eq(1)
      expect(reloaded['next_id']).to eq(2)
    end

    it 'falls back to the example file when no data file exists' do
      missing = File.join(tmp, 'absent.json')
      example = Chronicle::Store::EXAMPLE_PATH
      store = Chronicle::Store.load(data_path: missing, example_path: example)
      expect(store.campaign_name).not_to be_empty
      expect(File.exist?(missing)).to be false
    end
  end

  describe '#ensure_creature_references' do
    it 'creates an inactive reference for each npc lacking one, idempotently' do
      store = baseline
      store.add_entry(creature_payload(creature_id: 1001, active: true)) # already referenced

      created = store.ensure_creature_references([1001, 1002, 1003])
      expect(created).to eq(2) # 1002, 1003; 1001 already had one

      refs = store.list_entries(entry_type: 'creature')
      expect(refs.map { |e| e['creature_id'] }).to contain_exactly(1001, 1002, 1003)
      new_ones = refs.select { |e| [1002, 1003].include?(e['creature_id']) }
      expect(new_ones).to all(satisfy { |e| e['active'] == false })       # back-filled inactive
      expect(new_ones).to all(satisfy { |e| e['chapter'] == 1 })          # current chapter

      # Idempotent: a second call creates nothing.
      expect(store.ensure_creature_references([1001, 1002, 1003])).to eq(0)
    end
  end

  describe '#activate_creature_reference' do
    it 'creates an active reference when none exists' do
      store = baseline
      ref = store.activate_creature_reference(1005)
      expect(ref['creature_id']).to eq(1005)
      expect(ref['active']).to be(true)
      expect(store.list_entries(entry_type: 'creature').size).to eq(1)
    end

    it 'activates an existing (inactive) reference instead of duplicating it' do
      store = baseline
      store.add_entry(creature_payload(creature_id: 1006, active: false))
      store.activate_creature_reference(1006)
      refs = store.list_entries(entry_type: 'creature').select { |e| e['creature_id'] == 1006 }
      expect(refs.size).to eq(1)
      expect(refs.first['active']).to be(true)
    end
  end
end
