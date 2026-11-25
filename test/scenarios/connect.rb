require_relative 'support/scenario'

# Smoke test for the harness: four tablets and the DM's laptop on one server.
Scenarios.define 'connect: four tablets join and the DM assigns them' do
  step 'each tablet connects and waits unassigned' do
    party.each_value do |t|
      j = t.hello
      check j['ok'] == true, "#{t.name}: /api/hello failed"
      expect_eq j['character'], nil, "#{t.name}'s Character before assignment"
      t.sheet
      expect_eq t.last.status, 409, "#{t.name}'s sheet before assignment"
    end
  end

  step 'the DM assigns Ash, Lira and Thora by route' do
    %w[Ash Lira Thora].each { |n| check_ok dm.assign(party[n], ids[n]), "assign #{n}" }
  end

  step 'the DM assigns Garroth on the Status page', browser: true,
                                                   fast: -> { check_ok dm.assign(party['Garroth'], ids['Garroth']), 'assign Garroth' } do
    b = dm.browser
    b.go_to('/status')
    row = b.xpath("//tr[td[@class='assignment-id'][@title='#{party['Garroth'].device_id}']]").first
    check row, "Garroth's tablet is listed on the Status page"
    row.at_css('select[name=character_id]').select(ids['Garroth'].to_s, by: :value)
    row.at_css('form.assignment-form button, form.assignment-form input[type=submit]').click
    b.network.wait_idle
  end

  step 'every tablet now opens on its own Character' do
    party.each do |first, t|
      expect_eq t.hello.dig('character', 'id'), ids[first], "#{t.name}'s assigned Character id"
      expect_eq t.sheet['name'], t.name, "#{t.name}'s sheet"
    end
  end

  step 'scripted dice come out in order and none are unscripted' do
    dm.dice(10, 1, 6, reset: true)
    check_dice_scripted
    expect_eq dm.dice_status['queued'], [10, 1, 6], 'queued dice'
    dm.dice(reset: true)
  end

  step "the DM's browser takes its dice from the same queue", browser: true do
    dm.dice(7, 3, reset: true)
    faces = dm.browser.evaluate("await import('/js/randomRng.js').then(m => new m.RandomRng().rollDice(2, 10))")
    expect_eq faces, [7, 3], 'browser dice'
    check_dice_scripted
  end
end
