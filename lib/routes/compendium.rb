COMPENDIUM_VIEWS = %w[glossary].freeze

get '/compendium' do
  @view = COMPENDIUM_VIEWS.include?(params[:view]) ? params[:view] : 'glossary'
  @glossary_html = GlossaryDocs.render if @view == 'glossary'
  erb :compendium
end
