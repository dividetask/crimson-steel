require 'spec_helper'
require 'atlas'
require 'tmpdir'

# Externally-observable behavior of Atlas's public entry points, per
# docs/common/atlas/atlas_tests.md. Each State is built on a fresh tmp
# data path so persistence round-trips without touching the repo.
RSpec.describe Atlas::State do
  let(:tmpdir)    { Dir.mktmpdir('atlas-state') }
  let(:data_path) { File.join(tmpdir, 'atlas_data.json') }
  let(:state)     { described_class.new({}, data_path: data_path) }

  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  def add_forest = state.add_map(name: 'Forest Clearing', image: '/maps/forest.png', width: 50, height: 50)

  describe 'Manage Maps' do
    it 'Add Map assigns a unique ascending ID' do
      first = add_forest
      expect(first).to eq(1)
      expect(state.add_map(name: 'Second')).to be > first
    end

    it 'Add Map defaults archived to false' do
      expect(state.get_map(add_forest)[:archived]).to be false
    end

    it 'Add Map accepts null dimensions, then any coordinate places' do
      id = state.add_map(name: 'Unbounded', width: nil, height: nil)
      map = state.get_map(id)
      expect(map[:width]).to be_nil
      expect(state.place_token(map_id: id, creature_id: 7, x: 9999, y: -50)).to be_a(Integer)
    end

    it 'Add Map accepts arbitrarily large dimensions unchanged' do
      id = state.add_map(name: 'Huge', width: 100_000, height: 100_000)
      expect(state.get_map(id)[:width]).to eq(100_000)
    end

    it 'Edit Map updates only the supplied fields' do
      id = state.add_map(name: 'Old', width: 50)
      state.edit_map(id, name: 'New')
      map = state.get_map(id)
      expect(map[:name]).to eq('New')
      expect(map[:width]).to eq(50)
    end

    it 'Edit Map can grow the Map without moving Tokens' do
      id  = state.add_map(name: 'Grow', width: 50)
      tok = state.place_token(map_id: id, creature_id: 1, x: 40, y: 0)
      state.edit_map(id, width: 200)
      expect(state.get_map(id)[:width]).to eq(200)
      expect(state.get_token(tok)[:x]).to eq(40)
    end

    it 'Edit Map can shrink without dropping out-of-bounds Tokens' do
      id  = state.add_map(name: 'Shrink', width: 50)
      tok = state.place_token(map_id: id, creature_id: 1, x: 40, y: 0)
      state.edit_map(id, width: 30)
      expect(state.get_token(tok)[:x]).to eq(40)
    end

    it 'Get Map returns the full record including grid and archived' do
      map = state.get_map(add_forest)
      expect(map.keys).to include(:grid, :archived, :notes)
    end

    it 'Get Map on an unknown ID returns nil without error' do
      expect(state.get_map(999)).to be_nil
    end
  end

  describe 'Archive / Unarchive / Delete' do
    it 'Archive Map sets the flag and keeps the record retrievable' do
      id = add_forest
      state.archive_map(id)
      expect(state.get_map(id)[:archived]).to be true
    end

    it 'Archive Map preserves the Map\'s Tokens' do
      id = add_forest
      3.times { |i| state.place_token(map_id: id, creature_id: i, x: i, y: 0) }
      state.archive_map(id)
      expect(state.list_tokens(map_id: id).length).to eq(3)
    end

    it 'Archive Map clears the Active Map only when it matches' do
      keep = state.add_map(name: 'Keep')
      drop = state.add_map(name: 'Drop')
      state.set_active_map(keep)
      state.archive_map(drop)
      expect(state.active_map_id).to eq(keep)
      state.set_active_map(keep)
      state.archive_map(keep)
      expect(state.active_map_id).to be_nil
    end

    it 'Unarchive Map flips the flag back and does not restore Active Map' do
      id = add_forest
      state.set_active_map(id)
      state.archive_map(id)
      state.unarchive_map(id)
      expect(state.get_map(id)[:archived]).to be false
      expect(state.active_map_id).to be_nil
    end

    it 'Delete Map removes the Map and its Tokens' do
      id  = add_forest
      t1  = state.place_token(map_id: id, creature_id: 1, x: 0, y: 0)
      t2  = state.place_token(map_id: id, creature_id: 2, x: 1, y: 0)
      state.delete_map(id)
      expect(state.get_map(id)).to be_nil
      expect(state.get_token(t1)).to be_nil
      expect(state.get_token(t2)).to be_nil
    end

    it 'List Maps defaults to excluding archived' do
      a = state.add_map(name: 'A')
      state.add_map(name: 'B')
      state.add_map(name: 'C')
      state.archive_map(a)
      names = state.list_maps.map { |m| m[:name] }
      expect(names).to contain_exactly('B', 'C')
    end

    it 'List Maps include_archived returns everything' do
      a = state.add_map(name: 'A')
      state.add_map(name: 'B')
      state.archive_map(a)
      expect(state.list_maps(include_archived: true).length).to eq(2)
    end

    it 'List Maps archived_only returns only archived, ignoring include_archived' do
      a = state.add_map(name: 'A')
      state.add_map(name: 'B')
      state.archive_map(a)
      only = state.list_maps(archived_only: true, include_archived: false)
      expect(only.map { |m| m[:name] }).to eq(['A'])
    end
  end

  describe 'Active Map' do
    it 'Get Active Map returns nil on a fresh Atlas' do
      expect(state.get_active_map).to be_nil
    end

    it 'Set Active Map points at an existing, non-archived Map' do
      id = state.add_map(name: 'Battle')
      state.set_active_map(id)
      expect(state.get_active_map[:id]).to eq(id)
    end

    it 'Set Active Map to nil clears the pointer' do
      id = state.add_map(name: 'Battle')
      state.set_active_map(id)
      state.set_active_map(nil)
      expect(state.active_map_id).to be_nil
    end

    it 'Set Active Map refuses an archived Map' do
      id = state.add_map(name: 'Battle')
      state.archive_map(id)
      expect(state.set_active_map(id)).to eq(Atlas::ERROR)
      expect(state.active_map_id).to be_nil
    end

    it 'Set Active Map refuses an unknown Map' do
      expect(state.set_active_map(99)).to eq(Atlas::ERROR)
    end
  end

  describe 'Manage Tokens' do
    let(:map_id) { add_forest }

    it 'Place Token assigns a unique ascending ID' do
      first = state.place_token(map_id: map_id, creature_id: 1001, x: 10, y: 12)
      expect(first).to eq(1)
      expect(state.place_token(map_id: map_id, creature_id: 1002, x: 0, y: 0)).to be > first
    end

    it 'Place Token applies the default size' do
      id = state.place_token(map_id: map_id, creature_id: 1, x: 0, y: 0)
      expect(state.get_token(id)[:size]).to eq(Atlas::Config.default_token_size)
    end

    it 'Place Token preserves the supplied position verbatim' do
      id = state.place_token(map_id: map_id, creature_id: 1, x: 10.5, y: -3)
      tok = state.get_token(id)
      expect(tok[:x]).to eq(10.5)
      expect(tok[:y]).to eq(-3)
    end

    it 'Place Token outside the declared extent succeeds' do
      id = state.place_token(map_id: map_id, creature_id: 1, x: 100, y: 100)
      expect(state.get_token(id)[:x]).to eq(100)
    end

    it 'Place Token on an unknown Map returns the sentinel and creates nothing' do
      expect(state.place_token(map_id: 99, creature_id: 1, x: 0, y: 0)).to eq(Atlas::ERROR)
      expect(state.list_tokens.length).to eq(0)
    end

    it 'Move Token updates position and leaves other fields untouched' do
      id = state.place_token(map_id: map_id, creature_id: 1, x: 10, y: 12, size: 2)
      state.move_token(id, 20, 25)
      tok = state.get_token(id)
      expect([tok[:x], tok[:y]]).to eq([20, 25])
      expect(tok[:size]).to eq(2)
      expect(tok[:map_id]).to eq(map_id)
    end

    it 'Move Token is idempotent' do
      id = state.place_token(map_id: map_id, creature_id: 1, x: 5, y: 5)
      state.move_token(id, 7, 7)
      state.move_token(id, 7, 7)
      expect([state.get_token(id)[:x], state.get_token(id)[:y]]).to eq([7, 7])
    end

    it 'Edit Token updates supplied fields only' do
      id = state.place_token(map_id: map_id, creature_id: 1, x: 0, y: 0)
      state.edit_token(id, label: 'Goblin Boss')
      tok = state.get_token(id)
      expect(tok[:label]).to eq('Goblin Boss')
      expect(tok[:size]).to eq(Atlas::Config.default_token_size)
    end

    it 'Edit Token refuses to change id or map_id' do
      id = state.place_token(map_id: map_id, creature_id: 1, x: 0, y: 0)
      expect(state.edit_token(id, map_id: 99)).to eq(Atlas::ERROR)
      expect(state.get_token(id)[:map_id]).to eq(map_id)
    end

    it 'Remove Token deletes by ID; Get Token then returns nil' do
      id = state.place_token(map_id: map_id, creature_id: 1, x: 0, y: 0)
      state.remove_token(id)
      expect(state.get_token(id)).to be_nil
    end
  end

  describe 'List Tokens' do
    it 'returns everything with no filters and respects conjunctive filters' do
      m1 = state.add_map(name: 'M1')
      m2 = state.add_map(name: 'M2')
      state.place_token(map_id: m1, creature_id: '1001', x: 0, y: 0)
      state.place_token(map_id: m1, creature_id: '1002', x: 1, y: 0)
      state.place_token(map_id: m2, creature_id: '1001', x: 2, y: 0)

      expect(state.list_tokens.length).to eq(3)
      expect(state.list_tokens(map_id: m1).length).to eq(2)
      expect(state.list_tokens(creature_id: '1001').length).to eq(2)
      expect(state.list_tokens(map_id: m1, creature_id: '1001').length).to eq(1)
    end

    it 'include_hidden false excludes hidden Tokens' do
      m = state.add_map(name: 'M')
      state.place_token(map_id: m, creature_id: 1, x: 0, y: 0)
      state.place_token(map_id: m, creature_id: 2, x: 1, y: 0)
      state.place_token(map_id: m, creature_id: 3, x: 2, y: 0, hidden: true)
      expect(state.list_tokens(include_hidden: false).length).to eq(2)
      expect(state.list_tokens(include_hidden: true).length).to eq(3)
    end
  end

  describe 'Bulk operations' do
    it 'Place Tokens For Combat creates one Token per triple in order' do
      m = state.add_map(name: 'M')
      ids = state.place_tokens_for_combat(m, [[1001, 0, 0], [1002, 5, 0], [1003, 10, 0]])
      expect(ids.length).to eq(3)
      tokens = state.list_tokens(map_id: m)
      expect(tokens.map { |t| t[:creature_id] }).to eq([1001, 1002, 1003])
    end

    it 'Place Tokens For Combat with an empty list is a no-op' do
      m = state.add_map(name: 'M')
      expect(state.place_tokens_for_combat(m, [])).to eq([])
      expect(state.list_tokens(map_id: m)).to eq([])
    end

    it 'Clear Tokens On Map removes only that Map\'s Tokens' do
      m1 = state.add_map(name: 'M1')
      m2 = state.add_map(name: 'M2')
      4.times { |i| state.place_token(map_id: m1, creature_id: i, x: i, y: 0) }
      2.times { |i| state.place_token(map_id: m2, creature_id: i, x: i, y: 0) }
      state.clear_tokens_on_map(m1)
      expect(state.list_tokens(map_id: m1)).to eq([])
      expect(state.list_tokens(map_id: m2).length).to eq(2)
    end
  end

  describe 'Edge cases & persistence' do
    it 'persists maps, tokens, and the active pointer across a reload' do
      id  = add_forest
      state.set_active_map(id)
      # Atlas treats creature_id as opaque — a string supplied here round-trips
      # back as the same string (no coercion either way).
      state.place_token(map_id: id, creature_id: '1001', x: 3, y: 4)
      reloaded = described_class.load(data_path: data_path, example_path: '/nonexistent')
      expect(reloaded.list_maps.length).to eq(1)
      expect(reloaded.active_map_id).to eq(id)
      expect(reloaded.list_tokens.first[:creature_id]).to eq('1001')
    end

    it 'does not reuse deleted IDs' do
      a = state.add_map(name: 'A')
      b = state.add_map(name: 'B')
      state.delete_map(b)
      expect(state.add_map(name: 'C')).to eq(b + 1)
      _ = a
    end

    it 'returns a Token whose Creature was deleted (no validation)' do
      m  = state.add_map(name: 'M')
      id = state.place_token(map_id: m, creature_id: 1001, x: 0, y: 0)
      # Creatures domain removed 1001; Atlas still returns the Token intact.
      expect(state.get_token(id)[:creature_id]).to eq(1001)
    end

    it 'returns a Token referencing an unknown Map (cleanup is the consumer\'s)' do
      reloaded = described_class.new(
        { 'tokens' => [{ 'id' => 1, 'map_id' => 99, 'creature_id' => 1, 'x' => 0, 'y' => 0 }] },
        data_path: data_path
      )
      expect(reloaded.get_token(1)[:map_id]).to eq(99)
    end

    it 'honors a loaded active_map_id pointing at an archived Map' do
      reloaded = described_class.new(
        { 'maps' => [{ 'id' => 5, 'name' => 'Old', 'archived' => true }], 'active_map_id' => 5 },
        data_path: data_path
      )
      expect(reloaded.get_active_map[:id]).to eq(5)
    end
  end

  describe 'Zones' do
    let(:map_id) { add_forest }

    it 'Place Zone seeds a target anchor from the Creature\'s Token' do
      state.place_token(map_id: map_id, creature_id: 'c1', x: 10, y: 10)
      zid = state.place_zone(map_id: map_id, source_id: 'spell:1', shape: 'circle', size: 3,
                             anchor: { type: 'target', creature_id: 'c1' })
      zone = state.get_zone(zid)
      expect([zone[:anchor][:x], zone[:anchor][:y]]).to eq([10, 10])
    end

    it 'Place Zone with a target anchor but no Token returns the sentinel' do
      expect(state.place_zone(map_id: map_id, source_id: 's', shape: 'circle', size: 3,
                              anchor: { type: 'target', creature_id: 'ghost' })).to eq(Atlas::ERROR)
    end

    it 'stores and round-trips an optional texture' do
      zid = state.place_zone(map_id: map_id, source_id: 'spell:web', shape: 'circle', size: 4,
                             anchor: { type: 'point', x: 2, y: 2 }, texture: 'web')
      expect(state.get_zone(zid)[:texture]).to eq('web')
      reloaded = described_class.new(JSON.parse(JSON.generate(state.to_h)), data_path: data_path)
      expect(reloaded.get_zone(zid)[:texture]).to eq('web')
      # A textureless Zone simply has nil and is dropped from the serialized form.
      plain = state.place_zone(map_id: map_id, source_id: 'spell:plain', shape: 'square', size: 2,
                               anchor: { type: 'point', x: 1, y: 1 })
      expect(state.get_zone(plain)[:texture]).to be_nil
    end

    it 'a following Zone tracks its anchor Creature when the Token moves, notifying on membership change' do
      notes = []
      st = described_class.new({}, data_path: data_path, movement_notifier: ->(n) { notes << n })
      m  = st.add_map(name: 'M')
      tok = st.place_token(map_id: m, creature_id: 'c1', x: 0, y: 0)
      st.place_zone(map_id: m, source_id: 's', shape: 'square', size: 4,
                    anchor: { type: 'point', x: 100, y: 100 })
      caster_zone = st.place_zone(map_id: m, source_id: 'aura', shape: 'square', size: 4,
                                  anchor: { type: 'caster', creature_id: 'c1' })
      st.move_token(tok, 100, 100)
      # The caster's own aura followed it to (100,100).
      moved = st.get_zone(caster_zone)
      expect([moved[:anchor][:x], moved[:anchor][:y]]).to eq([100, 100])
      # Entering the point Zone at (100,100) emits a Movement Notification.
      expect(notes.last[:entered]).to include(1)
    end

    it 'Zones In Position reports overlap with a footprint' do
      m = state.add_map(name: 'M')
      zid = state.place_zone(map_id: m, source_id: 's', shape: 'square', size: 4,
                             anchor: { type: 'point', x: 10, y: 10 })
      expect(state.zones_in_position(m, 9, 9, 1)).to include(zid)
      expect(state.zones_in_position(m, 100, 100, 1)).not_to include(zid)
    end
  end

  describe 'Annotations' do
    let(:map_id) { add_forest }

    it 'Add Annotation stores an arrow with its points and assigns an id' do
      id = state.add_annotation(map_id: map_id, type: 'arrow', points: [[1, 2], [8, 9]],
                                color: '#ff0', author: 'player')
      expect(id).to be_a(Integer)
      ann = state.get_annotation(id)
      expect(ann[:type]).to eq('arrow')
      expect(ann[:points]).to eq([[1, 2], [8, 9]])
      expect(ann[:author]).to eq('player')
    end

    it 'Add Annotation stores a shape (rect/ellipse) and text' do
      rect = state.add_annotation(map_id: map_id, type: 'shape', shape_kind: 'rect', points: [[0, 0], [4, 3]])
      txt  = state.add_annotation(map_id: map_id, type: 'text', points: [[5, 5]], text: 'Ambush!')
      expect(state.get_annotation(rect)[:shape_kind]).to eq('rect')
      expect(state.get_annotation(txt)[:text]).to eq('Ambush!')
    end

    it 'Add Annotation on an unknown Map returns the sentinel' do
      expect(state.add_annotation(map_id: 99, type: 'arrow', points: [[0, 0], [1, 1]])).to eq(Atlas::ERROR)
    end

    it 'stores and round-trips the dm_only flag (defaults to false)' do
      plain  = state.add_annotation(map_id: map_id, type: 'text', points: [[1, 1]], text: 'seen')
      secret = state.add_annotation(map_id: map_id, type: 'text', points: [[2, 2]], text: 'hidden', dm_only: true)
      expect(state.get_annotation(plain)[:dm_only]).to eq(false)
      expect(state.get_annotation(secret)[:dm_only]).to eq(true)
      reloaded = described_class.load(data_path: data_path, example_path: '/nonexistent')
      expect(reloaded.get_annotation(secret)[:dm_only]).to eq(true)
    end

    it 'List Annotations filters conjunctively by map, type, and author' do
      other = state.add_map(name: 'Other')
      state.add_annotation(map_id: map_id, type: 'arrow', points: [[0, 0], [1, 1]], author: 'player')
      state.add_annotation(map_id: map_id, type: 'text',  points: [[2, 2]], text: 'x', author: 'dm')
      state.add_annotation(map_id: other,  type: 'arrow', points: [[0, 0], [1, 1]], author: 'player')
      expect(state.list_annotations(map_id: map_id).length).to eq(2)
      expect(state.list_annotations(map_id: map_id, type: 'arrow').length).to eq(1)
      expect(state.list_annotations(author: 'player').length).to eq(2)
      expect(state.list_annotations(map_id: map_id, author: 'dm').length).to eq(1)
    end

    it 'Remove Annotation deletes by id' do
      id = state.add_annotation(map_id: map_id, type: 'arrow', points: [[0, 0], [1, 1]])
      state.remove_annotation(id)
      expect(state.get_annotation(id)).to be_nil
    end

    it 'Edit Annotation updates text and points, but refuses id / map_id' do
      id = state.add_annotation(map_id: map_id, type: 'text', points: [[1, 1]], text: 'old', dm_only: true)
      state.edit_annotation(id, text: 'new', points: [[2, 3]])
      ann = state.get_annotation(id)
      expect(ann[:text]).to eq('new')
      expect(ann[:points]).to eq([[2, 3]])
      expect(ann[:dm_only]).to eq(true)         # untouched fields persist
      expect(state.edit_annotation(id, map_id: 999)).to eq(Atlas::ERROR)
      expect(state.edit_annotation(0xdead, text: 'x')).to eq(Atlas::ERROR)
    end

    it 'Clear Annotations On Map can scope to a single author' do
      state.add_annotation(map_id: map_id, type: 'arrow', points: [[0, 0], [1, 1]], author: 'player')
      state.add_annotation(map_id: map_id, type: 'shape', shape_kind: 'rect', points: [[0, 0], [2, 2]], author: 'dm')
      removed = state.clear_annotations_on_map(map_id, author: 'player')
      expect(removed).to eq(1)
      expect(state.list_annotations(map_id: map_id).map { |a| a[:author] }).to eq(['dm'])
      state.clear_annotations_on_map(map_id)
      expect(state.list_annotations(map_id: map_id)).to eq([])
    end

    it 'persists Annotations across a reload' do
      state.add_annotation(map_id: map_id, type: 'arrow', points: [[3, 4], [7, 8]], author: 'player')
      reloaded = described_class.load(data_path: data_path, example_path: '/nonexistent')
      ann = reloaded.list_annotations(map_id: map_id).first
      expect(ann[:points]).to eq([[3, 4], [7, 8]])
      expect(ann[:author]).to eq('player')
    end

    it 'Delete Map does not orphan Annotations the consumer cleared, but leaves them otherwise' do
      # Atlas cascades Tokens on Delete Map; Annotations are independent like
      # Zones — the consumer clears them. Here we just confirm they survive a
      # different map's deletion and are scoped by map_id.
      keep = state.add_annotation(map_id: map_id, type: 'arrow', points: [[0, 0], [1, 1]])
      other = state.add_map(name: 'Other')
      state.delete_map(other)
      expect(state.get_annotation(keep)).not_to be_nil
    end
  end

  describe 'Terrain' do
    let(:map_id) { add_forest }

    it 'Add Terrain stores a textured rectangle and assigns an id' do
      id = state.add_terrain(map_id: map_id, points: [[0, 0], [5, 4]], texture: 'wall.png')
      expect(id).to be_a(Integer)
      t = state.get_terrain(id)
      expect(t[:texture]).to eq('wall.png')
      expect(t[:shape_kind]).to eq('rect')        # default
      expect(t[:points]).to eq([[0, 0], [5, 4]])
    end

    it 'Add Terrain on an unknown Map returns the sentinel' do
      expect(state.add_terrain(map_id: 99, points: [[0, 0], [1, 1]], texture: 'dirt.png')).to eq(Atlas::ERROR)
    end

    it 'List Terrain filters by map' do
      other = state.add_map(name: 'Other')
      state.add_terrain(map_id: map_id, points: [[0, 0], [1, 1]], texture: 'dirt.png')
      state.add_terrain(map_id: map_id, points: [[2, 2], [3, 3]], texture: 'stone.png')
      state.add_terrain(map_id: other,  points: [[0, 0], [1, 1]], texture: 'wall.png')
      expect(state.list_terrain(map_id: map_id).length).to eq(2)
      expect(state.list_terrain.length).to eq(3)
    end

    it 'Remove and Clear Terrain delete fills' do
      a = state.add_terrain(map_id: map_id, points: [[0, 0], [1, 1]], texture: 'dirt.png')
      state.add_terrain(map_id: map_id, points: [[2, 2], [3, 3]], texture: 'stone.png')
      state.remove_terrain(a)
      expect(state.get_terrain(a)).to be_nil
      expect(state.clear_terrain_on_map(map_id)).to eq(1)
      expect(state.list_terrain(map_id: map_id)).to eq([])
    end

    it 'persists Terrain across a reload' do
      state.add_terrain(map_id: map_id, points: [[1, 1], [6, 5]], texture: 'wall.png', shape_kind: 'ellipse')
      reloaded = described_class.load(data_path: data_path, example_path: '/nonexistent')
      t = reloaded.list_terrain(map_id: map_id).first
      expect(t[:texture]).to eq('wall.png')
      expect(t[:shape_kind]).to eq('ellipse')
      expect(t[:points]).to eq([[1, 1], [6, 5]])
    end

    it 'Delete Map cascades to its Terrain (like Tokens)' do
      doomed = state.add_terrain(map_id: map_id, points: [[0, 0], [2, 2]], texture: 'dirt.png')
      state.delete_map(map_id)
      expect(state.get_terrain(doomed)).to be_nil
    end

    it 'Clear Annotations On Map never removes Terrain' do
      terrain = state.add_terrain(map_id: map_id, points: [[0, 0], [2, 2]], texture: 'stone.png')
      state.add_annotation(map_id: map_id, type: 'arrow', points: [[0, 0], [1, 1]])
      state.clear_annotations_on_map(map_id)
      expect(state.get_terrain(terrain)).not_to be_nil
    end

    it 'Erase Terrain Box punches a hole, leaving the surrounding ring' do
      state.add_terrain(map_id: map_id, points: [[0, 0], [10, 10]], texture: 'wall.png')
      affected = state.erase_terrain_box(map_id, 3, 3, 7, 7)
      expect(affected).to eq(1)
      fills = state.list_terrain(map_id: map_id)
      expect(fills.length).to eq(4)             # ring of four remainder rects
      # the erased hole is covered by none of the remainders
      covered = ->(x, y) { fills.any? { |t| xs = t[:points].map { |p| p[0] }; ys = t[:points].map { |p| p[1] }
                                            x >= xs.min && x < xs.max && y >= ys.min && y < ys.max } }
      expect(covered.call(5, 5)).to be(false)   # inside the hole
      expect(covered.call(1, 1)).to be(true)    # still walled
    end

    it 'Erase Terrain Box removes a fully-covered fill and reports zero on a miss' do
      a = state.add_terrain(map_id: map_id, points: [[2, 2], [4, 4]], texture: 'dirt.png')
      expect(state.erase_terrain_box(map_id, 0, 0, 10, 10)).to eq(1)
      expect(state.get_terrain(a)).to be_nil
      b = state.add_terrain(map_id: map_id, points: [[1, 1], [2, 2]], texture: 'dirt.png')
      expect(state.erase_terrain_box(map_id, 50, 50, 60, 60)).to eq(0)
      expect(state.get_terrain(b)).not_to be_nil
    end
  end
end
