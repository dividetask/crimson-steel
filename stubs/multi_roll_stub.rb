# Sinatra helper that renders the multi_roll_stub partial. The stub
# wraps N single roll_stubs in one panel with a top-level "Roll All"
# and "Confirm All". Each child is a regular roll_stub with show_confirm
# disabled, so all the per-row UI (Roll, Reroll Luck, Result/Crits
# inputs) lives in the single roll stub and stays consistent.
#
# rolls is a list of hashes; each hash is forwarded to roll_stub:
#   key             Stable identifier returned in the confirm payload.
#   character_name  Shown in the row header (e.g. "Alice").
#   check_name      Check type, rendered in parens (e.g. "Perception").
#   dice_count      Dice rolled for this row.
#   tn              Target number for this row.
#   starting_value  Starting successes/failures for this row (default 0).
#   luck_amount     Signed reroll count (positive = bonus, negative = penalty);
#                   0 to suppress the Luck row.
#   luck_label      Ability granting the luck reroll (e.g. "Bardic Inspiration").
#   insight_amount  Signed nudge amount; 0 to suppress the Insight row.
#   insight_label   Ability granting the insight bonus.
#
# Confirm All dispatches `multiroll:confirm` on the stub root with
# `{rows: [{key, successes, criticals}, ...]}` read from each child's
# editable Result/Crits inputs at confirm time.

helpers do
  def multi_roll_stub(rolls:, title: 'Rolls')
    stub_id = SecureRandom.hex(4)
    children = rolls.map do |r|
      h = r.transform_keys(&:to_sym)
      h[:_child_id] = SecureRandom.hex(4)
      h[:_key] = h[:key]
      h
    end
    erb :"stubs/_multi_roll_stub", layout: false, locals: {
      stub_id: stub_id,
      title: title,
      children: children
    }
  end
end

# Render the multi_roll_stub partial in response to an AJAX request from
# a parent stub (attack_stub uses this to swap in the rolls panel
# once the DM has finished selecting target / weapon / defense / etc.).
# The `rolls` parameter is a JSON-encoded array of row hashes; each
# row matches the `rolls:` shape that multi_roll_stub takes directly.
post '/multi_roll_stub/render' do
  content_type :html
  raw = params[:rolls].to_s
  rolls = raw.empty? ? [] : JSON.parse(raw)
  multi_roll_stub(
    rolls: rolls,
    title: params[:title].to_s.empty? ? 'Rolls' : params[:title].to_s
  )
end
