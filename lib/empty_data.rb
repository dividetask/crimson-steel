# EmptyData — production data source. Same surface as DummyData
# (every method, same return-shape) but every method returns the
# empty / minimal default. app.rb wires `DATA = EmptyData` in any
# non-development environment so DummyData is neither required
# nor invoked, and the only data the UI sees is whatever's in
# NotesState (data/notes_state.json).

class EmptyData
  EMPTY_CAMPAIGN     = { 'gold' => 0, 'rounds_elapsed' => 0,
                         'current_chapter' => nil, 'current_scene' => nil }.freeze
  EMPTY_COMBAT_STATE = { 'round' => 0, 'active_effects' => [],
                         'current_turn' => nil, 'turns' => [] }.freeze
  EMPTY_SCENE        = { 'title' => '', 'description' => '',
                         'show_initiative' => false }.freeze

  def self.campaign;               EMPTY_CAMPAIGN;     end
  def self.chapters;               [];                 end
  def self.characters;             [];                 end
  def self.pcs;                    [];                 end
  def self.character_by_id(_id);   nil;                end
  def self.enemy_groups;           [];                 end
  def self.enemy_templates;        [];                 end
  def self.combat_state;           EMPTY_COMBAT_STATE; end
  def self.initiative_turns;       [];                 end
  def self.notes;                  [];                 end
  def self.characters_of_interest; [];                 end
  def self.note_images;            [];                 end
  def self.note_maps;              [];                 end
  def self.note_map_by_id(_id);    nil;                end
  def self.spell_schools;          {};                 end
  def self.spell_list;             [];                 end
  def self.spell_by_name(_name);   nil;                end
  def self.all_skills;             [];                 end
  def self.store_items;            [];                 end
  def self.item_tree;              {};                 end
  def self.scene;                  EMPTY_SCENE;        end
end
