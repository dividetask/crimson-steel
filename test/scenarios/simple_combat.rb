require_relative 'support/scenario'

# docs/project/scenarios/simple_combat.md
Scenarios.define 'simple_combat: four Common Orcs', seed_data: 'no_monsters' do
  # Loot draws for common_orc_loadout (docs/common/equipment/loot_tables.yaml),
  # in table order: melee, ranged, ammunition, armor, shield (one-handed melee
  # only), copper, silver, gold, gem, necklace. Decimals are chance draws.
  orc_loot = [
    # 1: Falchion, Longbow, 12 Arrows, Hide armor, shield, 40 Copper, 25 Silver, small Gem, Necklace
    [0.25, 0.75, 3, 2, 3, 2, 2, 0.25, 0.1, 8, 8, 8, 8, 8, 0.1, 5, 5, 5, 5, 5, 0.5, 0.1, 0.2, 0.05],
    # 2: Great axe, Sling, 20 Stones, Leather armor, 30 Copper, 20 Gold, medium Gem
    [0.55, 0.25, 4, 4, 4, 4, 4, 0.6, 6, 6, 6, 6, 6, 0.5, 0.05, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 0.1, 0.5, 0.5],
    # 3: Long sword, Longbow, 10 Arrows, Breastplate, shield, 50 Copper, large Gem
    [0.65, 0.75, 2, 2, 2, 2, 2, 0.77, 0.1, 10, 10, 10, 10, 10, 0.5, 0.5, 0.1, 0.9, 0.5],
    # 4: Spear, Sling, 25 Stones, no armor, 20 Copper
    [0.95, 0.25, 5, 5, 5, 5, 5, 0.9, 4, 4, 4, 4, 4, 0.5, 0.5, 0.5, 0.5]
  ]

  expected_loot = [
    [['Falchion', 1, true], ['Longbow', 1, false], ['Arrow', 12, false], ['Hide armor', 1, true],
     ['Light metal shield', 1, true], ['Copper', 40, false], ['Silver', 25, false], ['Gem', 1, false, 5],
     ['Necklace of animal fangs', 1, false]],
    [['Great axe', 1, true], ['Sling', 1, false], ['Stone', 20, false], ['Leather armor', 1, true],
     ['Copper', 30, false], ['Gold', 20, false], ['Gem', 1, false, 15]],
    [['Long sword', 1, true], ['Longbow', 1, false], ['Arrow', 10, false], ['Breastplate', 1, true],
     ['Light metal shield', 1, true], ['Copper', 50, false], ['Gem', 1, false, 25]],
    [['Spear', 1, true], ['Sling', 1, false], ['Stone', 25, false], ['Copper', 20, false]]
  ]

  # Initiative dice per Combatant (sorted high to low; 10 shows as X). Turn
  # order: Thora, Orc 1, Ash, Orc 2, Orc 3, Lira, Orc 4, Garroth.
  init_dice = {
    'Thora Stoneveil' => [10, 10, 10, 9, 8, 7, 6, 5, 4, 3],
    'Ash Windmere'    => [10, 9, 9, 8, 7, 6, 5, 4, 3],
    'Lira Duskmoor'   => [10, 9, 7, 6, 5, 4, 3, 2],
    'Garroth Vask'    => [9, 8, 7, 5, 4, 3],
    'orc 1' => [10, 10, 9, 8], 'orc 2' => [10, 9, 8, 7], 'orc 3' => [10, 9, 8, 6], 'orc 4' => [9, 8, 7, 6]
  }

  helpers do
    define_method(:orc_loot) { orc_loot }
    define_method(:expected_loot) { expected_loot }
    define_method(:init_dice) { init_dice }

    def encounter = dm.http.get('/test/encounter').json
    def orcs = encounter['combatants'].select { _1['name'].to_s.match?(/\ACommon Orc( \d+)?\z/) }.sort_by { _1['id'] }
    def red_tier = dm.browser.at_xpath("//details[summary[normalize-space()='General Red Tier']]")
  end

  step 'the tablets connect and the DM assigns each its Character' do
    party.each_value(&:hello)
    party.each { |first, t| check_ok dm.assign(t, ids[first]), "assign #{first}" }
  end

  step 'the server starts with no monsters and the party at full health' do
    e = encounter
    check e['combatants'].none? { !ids.value?(_1['creature_id'].to_i) }, "monsters at start: #{e['combatants'].inspect}"
    party.each_value do |t|
      v = t.sheet['vitals'] || {}
      check v.dig('hp', 'max').to_i.positive?, "#{t.name}'s sheet has no HP"
      expect_eq v.dig('hp', 'current'), v.dig('hp', 'max'), "#{t.name}'s HP"
      expect_eq v.dig('mana', 'current'), v.dig('mana', 'max'), "#{t.name}'s mana"
      expect_eq v.dig('toxicity', 'current'), 0, "#{t.name}'s magic toxicity"
    end
  end

  step 'DM goes to Sheets', browser: true, fast: -> { check_ok dm.http.get('/character-sheets'), 'Sheets' } do
    dm.browser.go_to('/')
    dm.browser.at_xpath("//a[normalize-space()='Sheets']").click
    dm.browser.network.wait_idle
    check dm.browser.url.include?('/character-sheets'), "on #{dm.browser.url}"
  end

  step 'DM opens General Red Tier', browser: true do
    red_tier.at_css('summary').click
    check red_tier.evaluate('this.open'), 'General Red Tier is expanded'
  end

  step 'DM clicks Common Orc; General Red Tier stays expanded', browser: true do
    red_tier.at_xpath(".//li[@data-roster-kind='template'][@data-creature-id='307']/a").click
    dm.browser.network.wait_idle
    check dm.browser.url.include?('creature_id=307'), "on #{dm.browser.url}"
    check red_tier.evaluate('this.open'), 'General Red Tier is still expanded'
  end

  step 'DM clicks the plus next to Common Orc 4 times',
       browser: true, fast: -> { 4.times { check_ok dm.http.post_form('/encounter/spawn_and_add', template_id: 307), 'spawn' } } do
    4.times do
      red_tier.at_css('button.cs-roster-add[data-template-id="307"]').click
      dm.browser.network.wait_idle
      sleep 0.3
    end
    check red_tier.evaluate('this.open'), 'General Red Tier is still expanded'
  end

  step 'four Common Orcs are in the encounter, each with its planned loot' do
    list = orcs
    expect_eq list.size, 4, 'Common Orcs in the encounter'
    list.each_with_index do |o, i|
      got = dm.inventory("creature:#{o['creature_id']}").map do |s|
        row = [s['item'], s['quantity'], s['equipped']]
        s['item'] == 'Gem' ? row + [s['value_in_gold']] : row
      end
      expect_eq got.sort_by(&:to_s), expected_loot[i].sort_by(&:to_s), "Common Orc #{i + 1}'s loot"
    end
  end

  step 'DM goes to Encounter', browser: true, fast: -> { check_ok dm.http.get('/encounter'), 'Encounter' } do
    dm.browser.at_xpath("//a[normalize-space()='Encounter']").click
    dm.browser.network.wait_idle
  end

  step 'DM sets the phase to Combat', browser: true,
                                     fast: -> { check_ok dm.http.post_form('/encounter/set_phase', phase: 'combat'), 'set phase' } do
    sel = dm.browser.at_css('header select.phase-select, select.phase-select')
    sel.select('combat', by: :value)
    dm.browser.network.wait_idle
    sleep 0.5
    expect_eq encounter['phase'], 'combat', 'phase'
  end

  step 'DM clicks Start Combat', browser: true, fast: -> { check_ok dm.http.post_form('/encounter/start_combat'), 'start' } do
    dm.browser.at_css('button.initiative-start-combat').click
    dm.browser.network.wait_idle
  end

  step 'initiative order is Thora, Orc 1, Ash, Orc 2, Orc 3, Lira, Orc 4, Garroth' do
    e = encounter
    by_id = e['combatants'].to_h { [_1['id'], _1] }
    orc_no = orcs.each_with_index.to_h { |o, i| [o['id'], "orc #{i + 1}"] }
    names = e['order'].map { |id| orc_no[id] || by_id[id]['name'] }
    expect_eq names, ['Thora Stoneveil', 'orc 1', 'Ash Windmere', 'orc 2', 'orc 3', 'Lira Duskmoor', 'orc 4', 'Garroth Vask'],
              'turn order'
    expect_eq by_id[e['acting_combatant_id']]['name'], 'Thora Stoneveil', 'acting'
  end

  step 'the orcs are numbered Common Orc 1 to 4 on the tablets and the DM page', blocking: false do
    want = (1..4).map { "Common Orc #{_1}" }
    seen = { "Thora's tablet targets" => Array(party['Thora'].initiative['targets']).map { _1['name'] }.grep(/Common Orc/) }
    if browser_available?
      seen['DM Combat Tracker'] = dm.browser.css('.initiative-table td.initiative-col-name').map { _1.text.strip }.grep(/Common Orc/)
    end
    wrong = seen.reject { |_, names| names.sort == want }
    check wrong.empty?, wrong.map { |where, names| "#{where}: #{names.inspect}" }.join('; ')
  end

  step "Thora's tablet: Cast Standard Shield on Garroth" do
    garroth = encounter['combatants'].find { _1['name'] == 'Garroth Vask' }
    j = party['Thora'].request_action(key: 'cast:Standard Shield', target_id: garroth['id'].to_s)
    check j['ok'], "request: #{j.inspect}"
    expect_eq j.dig('flow', 'summary'), 'Standard Shield at Garroth Vask', 'request summary'
    check !j.dig('flow', 'blocking'), 'Standard Shield rolls nothing, so it does not hold up other requests'
  end

  # Spiritual Hammer is Tier 1 and always spends 2 dice: the tablet offers no
  # dice choice. Fails until that rule change lands (another thread).
  step "Thora's tablet: Cast Spiritual Hammer on Common Orc 1 (Tier 1, always 2 dice)", blocking: false do
    opt = Array(party['Thora'].initiative['options']).find { _1['key'] == 'cast:Spiritual Hammer' }
    check opt, "Thora's tablet offers Spiritual Hammer"
    choices = Array(opt['dice']).map { _1['dice'] }
    problems = []
    problems << "Tier #{opt['tier'].inspect}, expected 1" unless opt['tier'] == 1
    problems << "dice choices #{choices.inspect}, expected none or just 2" unless choices.empty? || choices == [2]
    body = { key: 'cast:Spiritual Hammer', target_id: orcs.first['id'].to_s }
    body[:dice] = choices.first if choices.size == 1
    j = party['Thora'].request_action(**body)
    if j['ok']
      problems << "Combat Pool cost #{j.dig('flow', 'pool_cost').inspect}, expected 2" unless j.dig('flow', 'pool_cost') == 2
      problems << "summary #{j.dig('flow', 'summary').inspect}" unless j.dig('flow', 'summary').to_s.include?('Spiritual Hammer')
    else
      problems << "request refused: #{j['error'] || j.inspect}"
    end
    check problems.empty?, problems.join('; ')
  end

  step "both requests wait on the DM's Player actions panel", blocking: false do
    html = dm.http.get('/encounter/flows_panel').body
    ['Standard Shield at Garroth Vask', 'Spiritual Hammer'].each do |s|
      check html.include?(s), "Player actions panel shows #{s}"
    end
  end

  step 'every die was scripted' do
    check_dice_scripted
  end

  before_step 'DM clicks the plus next to Common Orc 4 times' do
    dm.dice(orc_loot.flatten)
  end

  # Initiative rolls in the order the Combatants were added.
  before_step 'DM clicks Start Combat' do
    orc_no = orcs.each_with_index.to_h { |o, i| [o['id'], "orc #{i + 1}"] }
    faces = encounter['combatants'].sort_by { _1['id'] }.flat_map { |c| init_dice.fetch(orc_no[c['id']] || c['name']) }
    dm.dice(faces)
  end
end
