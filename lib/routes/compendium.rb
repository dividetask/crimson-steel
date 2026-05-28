COMPENDIUM_VIEWS = (['glossary'] + ExplainerDocs.keys).freeze

get '/compendium' do
  @view = COMPENDIUM_VIEWS.include?(params[:view]) ? params[:view] : 'glossary'

  if @view == 'glossary'
    @glossary_html = GlossaryDocs.render
  else
    @explainer_html  = ExplainerDocs.render(@view)
    @explainer_title = ExplainerDocs.title_for(@view)
  end

  erb :compendium
end
