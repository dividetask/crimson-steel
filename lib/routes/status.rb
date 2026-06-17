# Status — the DM's stub-preview surface. Each view renders one stub from
# self-contained sample data (never the live data/ directory). DM-only;
# players are bounced to the not-yet-implemented landing.
#
# Today it hosts the Combat encounter stub demo (the turn-action controls);
# more stubs join as they are built. See docs/website_design/combat.

STATUS_VIEWS = %w[combat].freeze

get '/status' do
  pass unless dm_view?            # players fall through to the not_found notice
  @view  = STATUS_VIEWS.include?(params[:view]) ? params[:view] : 'combat'
  @combat_blob = Combat::SampleTurn.blob
  erb :status
end
