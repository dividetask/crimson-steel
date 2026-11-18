require 'spec_helper'
require 'dice_resolution'
require_relative '../lib/action_flow'

# The player-driven attack flow (docs/project/action_flow.md), on a small
# hand-built Attack builder blob shaped like attack_builder_blob's.
RSpec.describe ActionFlow do
  def blob(with_shield: false, with_luck: false)
    rolls = [
      { id: 'attacker', side: 'supporting', creature_name: 'Ash', roll_name: 'Attack', dice_count: 2,
        bonus_penalty_list: [], speed: 0, excluded: false },
      { id: 'defender', side: 'opposing', creature_name: '—', roll_name: 'Defense', dice_count: 0,
        bonus_penalty_list: [], speed: 0, excluded: true },
      { id: 'shield', side: 'opposing', creature_name: '—', roll_name: 'Shield of Faith', dice_count: 0,
        bonus_penalty_list: [], speed: 0, excluded: true }
    ]
    atk = ->(n) { { set_dice: [{ id: 'attacker', count: n }], set_speed: [{ id: 'attacker', speed: 2 }],
                    set_bpl: [{ id: 'attacker', bonus_penalty_list: [['Competency', 1]] }] } }
    dodge = lambda do |n|
      { value: "dodge|#{n}", group: 'dodge', label: n.to_s, summary: "Dodge — #{n} dice", disabled: n > 3,
        patch: { set_bpl: [{ id: 'defender', bonus_penalty_list: [['Competency', 2]] }],
                 set_no_propagate: [{ id: 'defender', types: ['Competency'] }],
                 set_dice: [{ id: 'defender', count: n }], set_name: [{ id: 'defender', roll_name: 'Dodge' }],
                 set_excluded: [{ id: 'defender', excluded: false }] } }
    end
    steps = [
      { key: 'target', options: [{ value: 9, label: 'Goblin', patch: { set_name: [{ id: 'defender', creature_name: 'Goblin' }] } }] },
      { key: 'action', options: (2..4).map { |n| { value: "Rapier|#{n}", key: 'Rapier', summary: "Rapier — #{n} dice", patch: atk.call(n) } } },
      { key: 'defense', options_by: %w[target action],
        options_map: { '9|Rapier' => [{ value: 'none', group: 'none', label: 'No defense', summary: 'No defense',
                                        patch: { set_excluded: [{ id: 'defender', excluded: true }] } },
                                      dodge.call(4), { kind: 'info', value: 'dodge|info', label: '+2 Competency' }] +
                                     (2..4).map { |n| dodge.call(n) } } },
      { key: 'ally_defense', options_by: %w[target],
        options_map: with_shield ? { '9' => [{ value: 'none', summary: 'No defense', patch: { set_excluded: [{ id: 'shield', excluded: true }] } },
                                             { value: 'shield:5|2', group: 'shield', summary: 'Shield of Faith (Bryn) — 2 dice',
                                               patch: { set_dice: [{ id: 'shield', count: 2 }], set_excluded: [{ id: 'shield', excluded: false }] } }] } : {} }
    ]
    if with_luck
      steps << { key: 'luck:7', dynamic: 'luck', heading: 'Lira',
                 luck: { source: { id: 7, sid: '7', label: 'Lira', amount: 2, penalty: true },
                         targets: [{ roll_id: 'attacker', label: 'Ash' }, { roll_id: 'defender', label: 'Defender' }] } }
    end
    { rolls: rolls, steps: steps }
  end

  def flow(**kw)
    described_class.new(attacker_id: 1, attacker_name: 'Ash', turn_key: 't', blob: blob(**kw),
                        target_id: 9, action_value: 'Rapier|3', names: { 1 => 'Ash', 9 => 'Goblin', 5 => 'Bryn', 7 => 'Lira' })
  end

  it 'starts with the attacker’s request waiting for the DM' do
    f = flow
    expect(f.stage).to eq('declare')
    expect(f.tasks.first).to include('status' => 'submitted', 'owner_id' => 1)
    expect(f.tasks.first['summary']).to eq('Rapier — 3 dice at Goblin')
  end

  it 'asks the target for a defense once the DM approves, with the builder’s options' do
    f = flow
    f.approve(f.tasks.first['id'])
    expect(f.stage).to eq('respond')
    defense = f.open_tasks.first
    expect(defense).to include('step' => 'defense', 'owner_id' => 9, 'status' => 'waiting')
    opts = f.options_for(defense)
    expect(opts.map { |o| o[:value] }).to eq(%w[none dodge|2 dodge|3 dodge|4]) # info dropped, duplicate lead dropped, sorted
    expect(opts.find { |o| o[:value] == 'dodge|4' }[:disabled]).to be true
  end

  it 'needs DM approval for a player answer, and refuses a disabled option' do
    f = flow
    f.approve(f.tasks.first['id'])
    t = f.open_tasks.first
    expect { f.submit(t['id'], 'dodge|4') }.to raise_error(ArgumentError, /not available/)
    f.submit(t['id'], 'dodge|3')
    expect(f.stage).to eq('respond')
    f.approve(t['id'])
    expect(f.stage).to eq('roll')
  end

  it 'lets the DM send an answer back' do
    f = flow
    f.approve(f.tasks.first['id'])
    t = f.open_tasks.first
    f.submit(t['id'], 'dodge|2')
    f.reject(t['id'])
    expect(f.task(t['id'])).to include('status' => 'waiting', 'value' => nil)
  end

  it 'asks an ally shield and a Luck source, Luck only after the defense is known' do
    f = flow(with_shield: true, with_luck: true)
    f.approve(f.tasks.first['id'])
    expect(f.open_tasks.map { |t| [t['step'], t['owner_id']] }).to contain_exactly(['defense', 9], ['ally_defense', 5])
    f.open_tasks.each { |t| f.decide(t['id'], t['step'] == 'defense' ? 'dodge|2' : 'shield:5|2') }
    expect(f.stage).to eq('luck')
    luck = f.open_tasks.first
    expect(luck['owner_id']).to eq(7)
    values = f.options_for(luck).map { |o| o[:value] }
    expect(values).to include('7|none', '7|pos|2|attacker', '7|neg|2|defender')
    expect(values).not_to include('7|pos|3|attacker') # capped by the source's 2 Luck
  end

  it 'builds one roll per Roll in play, with propagated TNs, rerolls and owners' do
    f = flow(with_shield: true, with_luck: true)
    f.approve(f.tasks.first['id'])
    f.open_tasks.each { |t| f.decide(t['id'], t['step'] == 'defense' ? 'dodge|2' : 'shield:5|2') }
    f.decide(f.open_tasks.first['id'], '7|pos|1|attacker')
    expect(f.stage).to eq('roll')
    rolls = f.open_tasks.to_h { |t| [t['roll']['roll_id'], t] }
    expect(rolls.keys).to contain_exactly('attacker', 'defender', 'shield')
    expect(rolls['attacker']['owner_id']).to eq(1)
    expect(rolls['defender']['owner_id']).to eq(9)
    expect(rolls['shield']['owner_id']).to eq(5)
    atk = rolls['attacker']['roll']
    expect(atk).to include('dice_count' => 3, 'positive_reroll' => 1)
    # Attacker: +1 Competency, Dodge's Competency does not cross -> TN 7.
    expect(atk['tn']).to eq(DiceResolution.compute_target_number([['Competency', 1]])[:tn])
    # Defender: +2 Competency own, and the attacker's +1 crosses as a -1.
    expect(rolls['defender']['roll']['tn']).to eq(DiceResolution.compute_target_number([['Competency', 2], ['Competency', -1]])[:tn])
  end

  it 'scores a phone roll on the server and offers the DM a pre-fill when done' do
    f = flow
    f.approve(f.tasks.first['id'])
    f.decide(f.open_tasks.first['id'], 'none')
    t = f.open_tasks.first
    tn = t['roll']['tn']
    f.submit(t['id'], { 'dice' => [10, tn, 1], 'final' => [10, tn, 1], 'successes' => 99 })
    expect(f.task(t['id'])['value']['successes']).to eq(2 + 1 - 1) # 99 ignored
    f.approve(t['id'])
    expect(f.stage).to eq('resolve')
    expect(f.prefill[:choices]).to eq([%w[target 9], ['action', 'Rapier|3'], %w[defense none]])
    expect(f.prefill[:rolls]['attacker']['successes']).to eq(2)
  end

  it 'rejects a roll with the wrong number of dice' do
    f = flow
    f.approve(f.tasks.first['id'])
    f.decide(f.open_tasks.first['id'], 'none')
    expect { f.submit(f.open_tasks.first['id'], { 'dice' => [5] }) }.to raise_error(ArgumentError, /expected 3 dice/)
  end

  it 'lets the DM roll for a player' do
    f = flow
    f.approve(f.tasks.first['id'])
    f.decide(f.open_tasks.first['id'], 'none')
    t = f.open_tasks.first
    f.roll_for(t['id'], rng: Random.new(1))
    expect(f.task(t['id'])).to include('status' => 'approved', 'by' => 'dm')
    expect(f.stage).to eq('resolve')
  end

  describe '.apply_rerolls' do
    it 'rerolls the lowest non-Successes for a positive reroll and the highest Successes for a negative one' do
      rng = Class.new { def rand(_r) = 6 }.new
      final, rerolled = described_class.apply_rerolls([2, 9, 3, 7, 1], 7, 2, 1, rng)
      # Negative 1: the 9 (highest Success). Positive 2: the 1 and the 2 (lowest non-Successes).
      expect(rerolled).to eq([6, 6, nil, nil, 6])
      expect(final).to eq([6, 6, 3, 7, 6])
    end
  end

  describe '.propagate' do
    it 'inverts the other side, skipping no_propagate Types and Ascendancy' do
      sup = [{ 'id' => 'a', 'bonus_penalty_list' => [['Competency', 1], ['Ascendancy', 3]] }]
      opp = [{ 'id' => 'd', 'bonus_penalty_list' => [['Competency', 2]], 'no_propagate' => ['Competency'] },
             { 'id' => 's', 'bonus_penalty_list' => [['Guidance', 1]] }]
      out = described_class.propagate(sup, opp)
      expect(out['a']).to eq([['Competency', 1], ['Ascendancy', 3], ['Guidance', -1]])
      expect(out['d']).to eq([['Competency', 2], ['Competency', -1]])
      expect(out['s']).to eq([['Guidance', 1], ['Competency', -1]])
    end
  end
end
