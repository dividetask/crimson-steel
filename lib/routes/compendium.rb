# Player-facing views: the Glossary, the Spell and Class lists, plus every
# Explainer chapter. The DM additionally sees the DM-only "website design"
# pages (DesignDocs).
COMPENDIUM_PLAYER_VIEWS = (['glossary', 'spells', 'classes'] + ExplainerDocs.keys).freeze

get '/compendium' do
  # DesignDocs are DM-only. A player (or the DM viewing as a player) who
  # requests one of their keys is treated as if the page did not exist and
  # falls back to the default Glossary view.
  allowed = COMPENDIUM_PLAYER_VIEWS + (dm_view? ? DesignDocs.keys : [])
  @view = allowed.include?(params[:view]) ? params[:view] : 'glossary'

  if @view == 'glossary'
    @glossary_html = GlossaryDocs.render
  elsif @view == 'spells'
    @spells_list   = SpellList.rows
    @spell_schools = @spells_list.map { |r| r[:school] }.reject(&:empty?).uniq.sort
    @spell_skills  = @spells_list.flat_map { |r| r[:skills] }.uniq.sort
  elsif @view == 'classes'
    @classes_list = ClassList.rows
  elsif DesignDocs.keys.include?(@view)
    @explainer_html  = DesignDocs.render(@view)
    @explainer_title = DesignDocs.title_for(@view)
  else
    @explainer_html  = ExplainerDocs.render(@view)
    @explainer_title = ExplainerDocs.title_for(@view)
  end

  erb :compendium
end
