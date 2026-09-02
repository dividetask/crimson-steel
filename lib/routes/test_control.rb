# Test-control endpoints — mounted only when CRIMSON_TEST_MODE is set.
#
# A browser test arms the outcomes of the rolls the server makes before
# clicking the button that triggers them (see lib/test_control.rb). In a
# real run this file defines no routes at all, so there is nothing to
# reach even by accident.

if TestControl.enabled?
  # Arm predetermined outcomes.
  #
  #   POST /__test__/rolls
  #   { "initiative": { "Thora Stoneveil": "XX9853" },
  #     "encounter_seed": 20260902 }
  #
  # Keys are optional; an absent key leaves that source alone.
  post '/__test__/rolls' do
    halt 403 unless dm_host?
    content_type :json
    payload = (JSON.parse(request.body.read) rescue nil)
    halt 400, JSON.generate(ok: false, error: 'invalid payload') unless payload.is_a?(Hash)
    TestControl.arm(payload)
    JSON.generate(ok: true, initiative: TestControl.initiative,
                  encounter_seed: TestControl.encounter_seed)
  end

  # Forget everything armed. Called between tests.
  post '/__test__/reset' do
    halt 403 unless dm_host?
    content_type :json
    TestControl.reset!
    JSON.generate(ok: true)
  end
end
