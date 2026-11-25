# Test-only routes for scripted dice (lib/test_dice.rb). Loaded only when the
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
