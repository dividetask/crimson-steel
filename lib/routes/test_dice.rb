# Test-only routes: scripted dice (lib/test_dice.rb) and state checks. Loaded only when the
# server starts with CRIMSON_TEST_DICE=1; DM host only.
helpers do
  def require_test_dm!
    halt 403, { 'Content-Type' => 'application/json' }, '{"ok":false,"error":"DM only"}' unless dm_host?
  end

  def test_dice_json(payload) = [200, { 'Content-Type' => 'application/json' }, JSON.generate(payload)]
end

get '/test/dice' do
  require_test_dm!
  test_dice_json(TestDice.status)
end

post '/test/dice' do
  require_test_dm!
  body = (JSON.parse(request.body.read) rescue {})
  TestDice.reset! if body['reset']
  TestDice.push(body['faces'] || [])
  test_dice_json(TestDice.status)
end

# One die for the DM's browser (public/js/testDice.js).
get '/test/dice/next' do
  require_test_dm!
  size = params[:size].to_i
  test_dice_json(face: TestDice.next_face(1, size.positive? ? size : 10, 'browser'))
rescue ArgumentError => e
  [409, { 'Content-Type' => 'application/json' }, JSON.generate(ok: false, error: e.message)]
end

# An owner's Item Stacks, for checking generated loot ("creature:2003").
get '/test/inventory' do
  require_test_dm!
  stacks = Array(Equipment.instance.get_inventory(params[:owner].to_s))
  test_dice_json(stacks.map do |s|
    { item: s.item_type, quantity: s.quantity, equipped: s.equipped, value_in_gold: s.value_in_gold }
  end)
end

# The encounter as the server holds it: phase, combatants, turn order.
get '/test/encounter' do
  require_test_dm!
  es = encounter_state
  name = ->(c) { (Creatures.lookup(c[:creature_id])&.name rescue nil) }
  test_dice_json(
    phase: es.phase.to_s, acting_combatant_id: es.acting_combatant_id,
    combatants: es.combatants.map { |c| { id: c[:id], creature_id: c[:creature_id].to_s, name: name.call(c), initiative: c[:initiative_string] } },
    order: es.acting_combatants.map { _1[:id] }
  )
end
