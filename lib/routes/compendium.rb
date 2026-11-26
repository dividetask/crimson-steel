# The Compendium.
#
# Player-facing: the Glossary, the Spell and Class lists, and every chapter
# of the player's manual — a chapter being a concept under docs/common/
# whose design doc carries an @chapter directive (see CommonDocs).
#
# DM-only, on top of that: the full Common Rules page for every concept
# (player prose and implementer rules together, plus config and tests), a
# coverage overview of the whole docs/common/ tree, and the website-design
# pages under docs/website_design/ (DesignDocs).
COMPENDIUM_STATIC_VIEWS = %w[glossary spells classes].freeze

# Chapters used to be keyed by a short name before the concept folder
# became the key. Old links keep working.
COMPENDIUM_CHAPTER_ALIASES = {
  'dice'   => 'dice_resolution',
  'checks' => 'check_resolution'
}.freeze

COMMON_VIEW_PREFIX  = 'common:'.freeze
COMMON_COVERAGE_KEY = 'common'.freeze

get '/compendium' do
  requested = COMPENDIUM_CHAPTER_ALIASES.fetch(params[:view].to_s, params[:view].to_s)

  concepts     = CommonDocs.concepts
  player_views = COMPENDIUM_STATIC_VIEWS + CommonDocs.chapters.map(&:key)
  dm_views     = if dm_view?
                   [COMMON_COVERAGE_KEY] +
                     concepts.map { |c| "#{COMMON_VIEW_PREFIX}#{c.key}" } +
                     DesignDocs.keys
                 else
                   []
                 end

  # Anything else — including a DM-only key requested by a player — is
  # treated as if the page did not exist and falls back to the Glossary.
  @view = (player_views + dm_views).include?(requested) ? requested : 'glossary'

  case @view
  when 'glossary'
    @glossary_html = GlossaryDocs.render
  when 'spells'
    @spells_list   = SpellList.rows
    @spell_schools = @spells_list.map { |r| r[:school] }.reject(&:empty?).uniq.sort
    @spell_skills  = @spells_list.flat_map { |r| r[:skills] }.uniq.sort
  when 'classes'
    @classes_list = ClassList.rows
  when COMMON_COVERAGE_KEY
    # Same ordering as the nav: chapters first, then everything else.
    @coverage = CommonDocs.in_nav_order
  else
    if @view.start_with?(COMMON_VIEW_PREFIX)
      render_common_concept(@view.delete_prefix(COMMON_VIEW_PREFIX), :dm)
    elsif (concept = concepts.find { |c| c.key == @view })
      render_common_concept(concept.key, :player)
    else
      @explainer_html  = DesignDocs.render(@view)
      @explainer_title = DesignDocs.title_for(@view)
    end
  end

  erb :compendium
end

# One concept page, for one audience. The player gets the chapter — the
# @player passages and the config values players are allowed to see. The
# DM gets the whole merged document (player passages marked as such), the
# full config table, and the canonical tests.
def render_common_concept(key, audience)
  @concept  = CommonDocs.find(key)
  return unless @concept

  @audience    = audience
  @doc_html    = CommonDocs.render_design(@concept, audience: audience)
  @config_html = CommonDocs.render_config(@concept, audience: audience)
  @tests_html  = audience == :dm ? CommonDocs.render_tests(@concept) : ''
end
