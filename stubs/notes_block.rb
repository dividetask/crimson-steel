# notes_block — composes the four notes sections (journal,
# characters of interest, images, maps) into one rendered block.
# Both /notes and /scene render exactly the same four sections;
# the only real differences are the active_only filter and which
# DM forms are shown. Centralizing the composition here keeps the
# page templates thin and prevents drift between them.

helpers do
  def notes_block(current_chapter: nil, active_only: false,
                  scene_state: nil, interactive_maps: false,
                  editable_journal: false,
                  editable_images: false,
                  show_journal_add: false,
                  show_create_map: false,
                  show_archived_maps: false,
                  section_order: %w[journal characters images maps])
    erb :"stubs/_notes_block", layout: false, locals: {
      current_chapter:    current_chapter,
      active_only:        active_only,
      scene_state:        scene_state,
      interactive_maps:   interactive_maps,
      editable_journal:   editable_journal,
      editable_images:    editable_images,
      show_journal_add:   show_journal_add,
      show_create_map:    show_create_map,
      show_archived_maps: show_archived_maps,
      section_order:      section_order
    }
  end
end
