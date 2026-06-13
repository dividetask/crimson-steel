# Compendium — the player-facing rules browser. The left nav lists one
# entry per game-rules chapter overview (docs/game_rules/<chapter>/
# <chapter>_overview.md), with the Glossary pinned last. See
# docs/website_design/compendium.md.

get '/compendium' do
  views   = CompendiumDocs.view_keys
  default = views.first || 'glossary'
  @view   = views.include?(params[:view]) ? params[:view] : default

  @nav_items = CompendiumDocs.nav_items
  @title     = CompendiumDocs.title_for(@view)

  if @view == 'glossary'
    @glossary_html = CompendiumDocs.render_glossary
  else
    @overview_html = CompendiumDocs.render_overview(@view)
    @has_mermaid   = @overview_html ? CompendiumDocs.overview_has_mermaid?(@overview_html) : false
  end

  erb :compendium
end
