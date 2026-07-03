COMPENDIUM_VIEWS = (['glossary', 'spells'] + ExplainerDocs.keys).freeze

get '/compendium' do
  @view = COMPENDIUM_VIEWS.include?(params[:view]) ? params[:view] : 'glossary'

  if @view == 'glossary'
    @glossary_html = GlossaryDocs.render
  elsif @view == 'spells'
    @spells_list   = SpellList.rows
    @spell_schools = @spells_list.map { |r| r[:school] }.reject(&:empty?).uniq.sort
    @spell_skills  = @spells_list.flat_map { |r| r[:skills] }.uniq.sort
  else
    @explainer_html  = ExplainerDocs.render(@view)
    @explainer_title = ExplainerDocs.title_for(@view)
  end

  erb :compendium
end
