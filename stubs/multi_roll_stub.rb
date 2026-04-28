# Sinatra helper that renders the multi_roll_stub partial. The stub
# displays N rolls side-by-side and lets the DM roll them all at once
# (or individually), apply per-roll luck rerolls, and confirm the
# whole batch. Each row is independent on the server (its own session
# token via /roll_stub/roll), but the UI presents them as one panel
# with a top-level "Roll All".
#
# Rolls is a list of hashes:
#   key                Stable identifier for the row (returned in the confirm payload).
#   label              Row heading shown to the DM.
#   dice_count         Dice rolled for this row.
#   tn                 Target number for this row.
#   starting_value     Starting successes/failures for this row (default 0).
#   luck_amount        Reroll-N-lowest count per click of the Bardic button (0 to suppress).
#   luck_label         Button label for the bonus luck (e.g. "Bardic Inspiration").
#   unsettling_amount  Reroll-N-highest count per click (0 to suppress).
#   unsettling_label   Button label for the penalty luck (e.g. "Unsettling Words").
#
# The Confirm All button dispatches `multiroll:confirm` on the stub root
# with `{rows: [{key, successes, criticals, dice_count, tn}, ...]}`.

helpers do
  def multi_roll_stub(rolls:, title: 'Rolls')
    erb :"stubs/_multi_roll_stub", layout: false, locals: {
      stub_id: SecureRandom.hex(4),
      title: title,
      rolls: rolls
    }
  end
end

# Render the multi_roll_stub partial in response to an AJAX request from
# a parent stub (melee_attack_stub uses this to swap in the rolls panel
# once the DM has finished selecting target / weapon / defense / etc.).
post '/multi_roll_stub/render' do
  content_type :html
  raw = params[:rolls].to_s
  rolls = raw.empty? ? [] : JSON.parse(raw)
  multi_roll_stub(
    rolls: rolls,
    title: params[:title].to_s.empty? ? 'Rolls' : params[:title].to_s
  )
end
