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

  # Phones: Goblin (9) has none; Bryn (5), Lira (7) and Ash (1) do.
  let(:claimed) { ->(cid) { [1, 5, 7].include?(cid) } }

  def defense_step
    { 'key' => 'defense', 'options' => [
      { 'value' => 'none', 'label' => 'No defense', 'summary' => 'No defense' },
      { 'value' => 'dodge|2', 'group' => 'dodge', 'label' => '2', 'summary' => 'Dodge — 2 dice' },
      { 'value' => 'dodge|3', 'group' => 'dodge', 'label' => '3', 'summary' => 'Dodge — 3 dice', 'disabled' => true }
    ] }
  end

  def roll(id, n: 3, tn: 7)
    { 'id' => id, 'side' => id == 'attacker' ? 'supporting' : 'opposing', 'creature_name' => id, 'roll_name' => 'Dodge',
      'dice_count' => n, 'tn' => tn, 'starting_value' => 0, 'bonus_penalty_list' => [['Competency', 2]] }
  end

  # A DM-started attack by the Goblin (9) on Ash (1).
  def dm_flow
    described_class.new(kind: 'attack', actor_id: 9, actor_name: 'Goblin', turn_key: 't', blob: nil, dm_started: true,
                        names: { 1 => 'Ash', 9 => 'Goblin', 5 => 'Bryn', 7 => 'Lira' })
  end

  it 'starts with the attacker’s request waiting for the DM' do
    f = flow
    expect(f.stage).to eq('declare')
    expect(f.tasks.first).to include('status' => 'submitted', 'owner_id' => 1)
    expect(f.tasks.first['summary']).to eq('Rapier — 3 dice at Goblin')
  end

  it 'opens in the builder once the DM approves, with the player’s choices' do
    f = flow
    f.approve(f.tasks.first['id'])
    expect(f.stage).to eq('builder')
    expect(f.needs_open).to be true
    expect(f.prefill[:choices]).to eq([%w[target 9], ['action', 'Rapier|3']])
    f.sync!({ 'choices' => { 'target' => '9' } }, claimed: claimed)
    expect(f.needs_open).to be false
    expect(f.live?).to be true
  end

  it 'asks a player with a phone for their defense, and takes their answer' do
    f = dm_flow
    f.sync!({ 'choices' => { 'target' => '1' }, 'target_id' => 1, 'action_label' => 'Claws', 'step' => defense_step }, claimed: claimed)
    t = f.choice_tasks.first
    expect(t).to include('owner_id' => 1, 'step' => 'defense', 'status' => 'waiting')
    expect(f.options_for(t).map { |o| o[:value] }).to eq(%w[none dodge|2 dodge|3])
    expect(f.options_for(t).find { |o| o[:value] == 'dodge|3' }[:disabled]).to be true
    expect(f.builder_view[:waiting_on]).to eq('Ash')
    expect { f.submit(t['id'], 'dodge|3') }.to raise_error(ArgumentError, /not available/)
    f.submit(t['id'], 'dodge|2')
    expect(f.builder_view[:answer]).to eq(step: 'defense', value: 'dodge|2')
    expect(f.headline([1])).to eq('Goblin attacking with Claws at you')
    # The builder moved on (it picked the answer, or the DM chose): the prompt goes away.
    f.sync!({ 'choices' => { 'target' => '1', 'defense' => 'dodge|2' }, 'step' => nil }, claimed: claimed)
    expect(f.choice_tasks).to be_empty
  end

  it 'asks nobody when the one deciding has no phone' do
    f = flow
    f.approve(f.tasks.first['id'])
    f.sync!({ 'choices' => { 'target' => '9' }, 'step' => defense_step }, claimed: claimed)
    expect(f.choice_tasks).to be_empty
  end

  it 'asks the shielding ally and each Luck source on their phones' do
    f = dm_flow
    shield = { 'key' => 'ally_defense', 'options' => [{ 'value' => 'none' }, { 'value' => 'shield:5|2', 'summary' => 'Shield — 2 dice' }] }
    f.sync!({ 'choices' => { 'target' => '1' }, 'step' => shield }, claimed: claimed)
    expect(f.choice_tasks.first['owner_id']).to eq(5)
    luck = { 'key' => 'luck:7', 'luck' => { 'source' => { 'id' => 7, 'sid' => '7', 'label' => 'Lira', 'penalty' => true },
                                            'targets' => [{ 'roll_id' => 'attacker', 'label' => 'Goblin', 'cap' => 2 },
                                                          { 'roll_id' => 'defender', 'label' => 'Ash', 'cap' => 0 }] } }
    f.sync!({ 'choices' => { 'target' => '1' }, 'step' => luck }, claimed: claimed)
    t = f.choice_tasks.first
    expect(t['owner_id']).to eq(7)
    expect(f.options_for(t).map { |o| o[:value] }).to eq(['7|none', '7|pos|1|attacker', '7|pos|2|attacker', '7|neg|1|attacker', '7|neg|2|attacker'])
  end

  it 'reads an attack by its weapon type, from the viewer’s side' do
    f = dm_flow
    f.sync!({ 'choices' => { 'target' => '1', 'action' => 'Great sword|7' }, 'target_id' => 1,
              'action_label' => '+2 Vicious Great sword' }, claimed: claimed)
    expect(f.title_line([7])).to eq('Goblin Attacks Ash with Great Sword')
    expect(f.title_line([1])).to eq('Goblin Attacks You with Great Sword')
  end

  it 'labels Luck as Help / Hinder each Roll, with how much Luck is left' do
    f = dm_flow
    luck = { 'key' => 'luck:7', 'luck' => { 'source' => { 'id' => 7, 'sid' => '7', 'label' => 'Lira', 'amount' => 3, 'penalty' => true },
                                            'targets' => [{ 'roll_id' => 'attacker', 'label' => 'Goblin’s Attack', 'cap' => 1 }] } }
    f.sync!({ 'choices' => {}, 'step' => luck }, claimed: claimed)
    t = f.choice_tasks.first
    expect(t['luck_amount']).to eq(3)
    expect(f.options_for(t).map { |o| [o[:group_label], o[:tone]] })
      .to eq([['No luck', nil], ['Help Goblin’s Attack', 'help'], ['Hinder Goblin’s Attack', 'hinder']])
  end

  describe 'rolls' do
    def rolling(f)
      f.sync!({ 'choices' => { 'target' => '1', 'dice' => '3|arcana' }, 'step' => nil,
                'rolls' => [roll('attacker'), roll('defender', n: 2)] }, claimed: claimed)
    end

    it 'gives a player with a phone their own roll; the rest are the DM’s' do
      f = dm_flow
      rolling(f)
      atk, dfn = f.roll_tasks
      expect(atk).to include('owner_id' => 9, 'claimed' => false)
      expect(dfn).to include('owner_id' => 1, 'claimed' => true)
      expect(dfn['roll']).to include('what' => 'Dodging', 'bonus' => 2, 'dice_count' => 2)
    end

    it 'keeps a roll to the DM until approved; a player’s roll replaces the DM’s' do
      f = dm_flow
      rolling(f)
      t = f.roll_tasks.last
      f.roll_for(t['id'], rng: Random.new(1))
      expect(f.dm_pending?(t)).to be true
      expect(f.builder_view[:rolls]['defender']).to include(status: 'submitted', by: 'dm')
      hidden = f.public_roll_overview([1]).find { |r| r[:task_id] == t['id'] }
      expect(hidden).to include(status: 'waiting', final: nil)
      # Ash rolls on the phone anyway: theirs replaces the DM's, still unapproved.
      f.submit(t['id'], { 'dice' => [9, 9], 'final' => [9, 9] })
      expect(t).to include('by' => 'player', 'status' => 'submitted')
      expect(f.public_roll_overview([1]).find { |r| r[:task_id] == t['id'] }[:final]).to eq([9, 9]) # Ash sees their own
      expect(f.public_roll_overview([5]).find { |r| r[:task_id] == t['id'] }[:final]).to be_nil    # others do not
      f.approve(t['id'])
      expect(f.public_roll_overview([5]).find { |r| r[:task_id] == t['id'] }[:final]).to eq([9, 9])
      expect { f.submit(t['id'], { 'dice' => [1, 1] }) }.to raise_error(ArgumentError, /finished/)
    end

    it 'rolls again when the dice or TN change under a roll' do
      f = dm_flow
      rolling(f)
      t = f.roll_tasks.last
      f.submit(t['id'], { 'dice' => [9, 9] })
      f.sync!({ 'choices' => {}, 'rolls' => [roll('attacker'), roll('defender', n: 3)] }, claimed: claimed)
      expect(f.roll_tasks.last).to include('status' => 'waiting', 'value' => nil)
    end

    it 'counts each Confirm, so every phone throws the shared rolls once' do
      store = ActionFlows.new
      f = store.add(dm_flow)
      rolling(f)
      expect(store.recent_shared).to be_empty
      f.share!('attacker' => { 'dice' => [1, 3, 7], 'rerolled' => [6, nil, nil], 'final' => [6, 3, 7] })
      expect(f.shared_version).to eq(1)
      expect(store.recent_shared).to eq([f])
      expect(f.public_roll_overview([5]).first).to include(dice: [1, 3, 7], rerolled: [6, nil, nil], final: [6, 3, 7])
    end

    it 'shares every roll on Confirm, scoring the ones the builder rolled' do
      f = dm_flow
      rolling(f)
      atk, dfn = f.roll_tasks
      f.submit(dfn['id'], { 'dice' => [2, 8] })
      f.share!('attacker' => { 'dice' => [10, 3, 7], 'final' => [10, 3, 7] })
      expect(atk).to include('status' => 'approved')
      expect(atk['value']).to include('successes' => 3, 'crits' => 1)
      expect(dfn['status']).to eq('approved')
      expect(f.public_roll_overview([5]).map { |r| r[:final] }).to eq([[10, 3, 7], [2, 8]])
    end

    it 'gives the attacker their Damage Rider dice, where a 1 takes nothing away' do
      f = dm_flow
      rider = { 'id' => 'rider-0', 'creature_name' => 'Vicious', 'roll_name' => '(slashing)', 'dice_count' => 4, 'tn' => 3,
                'starting_value' => 0, 'failure_modifier' => 0 }
      f.sync!({ 'choices' => {}, 'rolls' => [rider] }, claimed: claimed)
      t = f.roll_tasks.first
      expect(t).to include('owner_id' => 9)
      expect(t['roll']).to include('name' => 'Vicious', 'what' => 'Vicious', 'failure_modifier' => 0)
      f.share!('rider-0' => { 'dice' => [1, 1, 10, 5] })
      expect(t['value']['successes']).to eq(3)
    end

    it 'clears the prompts when the builder is hidden' do
      f = dm_flow
      rolling(f)
      f.sync!({ 'idle' => true }, claimed: claimed)
      expect(f.roll_tasks).to be_empty
    end
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


  describe 'reactions (Kesser\'s Gambit)' do
    let(:spec) { { 'name' => "Kesser's Gambit", 'tn' => 5, 'starting_value' => 0, 'positive_reroll' => 0, 'negative_reroll' => 0 } }
    let(:luck) do
      { 'key' => 'luck:7', 'luck' => { 'source' => { 'id' => 7, 'sid' => '7', 'label' => 'Lira', 'penalty' => true },
                                       'targets' => [{ 'roll_id' => 'attacker', 'label' => 'Goblin', 'cap' => 2 }] } }
    end

    it 'offers it, gives the Channel check to the phone, and keeps it across builder syncs' do
      f = flow
      f.sync!({ 'choices' => { 'target' => '9' } }, claimed: claimed)
      offer = f.offer_reaction(5, ability: "Kesser's Gambit", mana_cost: 4, dice: [2, 3], roll: spec)
      expect(f.options_for(offer).map { |o| o[:value] }).to eq(%w[none gambit|2 gambit|3])
      f.submit(offer['id'], 'gambit|3')
      roll = f.roll_tasks.find { |t| t['step'] == 'roll:gambit-5' }
      expect(roll['roll']['dice_count']).to eq(3)
      expect(roll['claimed']).to be(true)
      f.sync!({ 'choices' => { 'target' => '9' } }, claimed: claimed)
      expect(f.task(roll['id'])).not_to be_nil
      f.submit(roll['id'], { 'dice' => [6, 2, 9], 'final' => [6, 2, 9] })
      r = f.builder_view[:reactions].first
      expect(r).to include(owner: 'Bryn', dice: 3, rolled: true)
      expect(f.reaction_used?(5)).to be(true)
    end

    it 'is used up by Luck, and once used greys out that player\'s Luck' do
      f = flow
      f.sync!({ 'choices' => { 'target' => '9' }, 'step' => luck }, claimed: claimed)
      f.submit(f.choice_tasks.first['id'], '7|pos|1|attacker')
      f.sync!({ 'choices' => { 'target' => '9', 'luck:7' => '7|pos|1|attacker' } }, claimed: claimed)
      expect(f.reaction_used?(7)).to be(true)

      g = flow
      g.sync!({ 'choices' => { 'target' => '9' } }, claimed: claimed)
      offer = g.offer_reaction(7, ability: "Kesser's Gambit", mana_cost: 4, dice: [2], roll: spec)
      g.submit(offer['id'], 'gambit|2')
      g.sync!({ 'choices' => { 'target' => '9' }, 'step' => luck }, claimed: claimed)
      t = g.choice_tasks.find { |x| x['step'] == 'luck:7' }
      expect(g.options_for(t).reject { |o| o[:group] == 'none' }.map { |o| o[:disabled] }.uniq).to eq([true])
    end
  end
end
