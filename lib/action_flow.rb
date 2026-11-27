require 'set'
require 'securerandom'
require 'cgi'

# An action in progress (docs/project/action_flow.md): an Attack, a Cast, an
# Item, or a Special Ability, run in the DM's own Action Builder with every
# player who has a part in it answering on their phone.
#
# Two ways in:
#
# * **A player asks** from the Android app. The flow starts at `declare`
#   (their choices: Target, Weapon / Spell and dice…). When the DM approves,
#   it moves to `builder`: the DM's Encounter page opens the matching builder
#   with those choices made, exactly as if the DM had pressed Attack.
# * **The DM starts it** in the builder. The flow is created by the builder
#   itself on its first sync, straight at `builder` (dm_started).
#
# In `builder`, the builder is in charge: every second or so it sends its
# state (#sync!) — the step it is on, its options, and once the dice are up,
# every Roll. The flow mirrors that onto the phones:
#
# * A step that is a player's choice — the target's Defense, an ally's
#   Shield, a Luck source's Bardic Inspiration — becomes a prompt on that
#   player's phone. Their answer is picked in the builder by itself. When the
#   DM picks first, the builder moves on and the prompt goes away.
# * Each Roll owned by a player with a phone ("claimed") can be rolled on
#   that phone, or by the DM ("Roll for …"). Either way only the DM sees it
#   until the DM approves it; a player's roll replaces a DM roll not yet
#   approved. Unclaimed Rolls (enemies, NPCs, players without the app) are
#   rolled by the builder's Roll All. Confirm shares everything.
#
# The DM's commit (resolve_attack / resolve_cast / use_special with the
# flow_id) closes the flow.
class ActionFlow
  STAGES = %w[declare builder].freeze
  KINDS = %w[attack cast item special].freeze
  # A builder not heard from for this long (no change sent, no fetch — the
  # page fetches at least every 30 seconds) is treated as closed: the Player
  # actions panel offers "Open in … builder" again.
  STALE_SECONDS = 75

  # The DM's fudge for a player's roll (docs/project/action_flow.md → Fudging):
  # the phone rolls as usual, then — before any Luck reroll — changes the
  # fewest dice it must, to random values, so the Degree of Success lands in
  # the chosen band. Never shown to anyone; the DM's own rolls are untouched.
  FUDGES = %w[none success failure crit fumble].freeze
  FUDGE_LABELS = { 'none' => 'No fudge', 'success' => 'Success', 'failure' => 'Failure',
                   'crit' => 'Critical', 'fumble' => 'Fumble' }.freeze

  # Steps the other players answer; every other step is the actor's own
  # choice, which the DM makes in the builder.
  PLAYER_STEPS = /\A(defense|ally_defense|luck:.+)\z/

  attr_reader :id, :kind, :actor_id, :actor_name, :turn_key, :blob, :choices, :tasks, :rolls, :created_at, :ability,
              :last_sync
  attr_accessor :stage, :status, :needs_open
  attr_reader :category

  # +kind+: attack / cast / item / special. +blob+: the builder blob (symbol
  # keys) of a player's request, or nil. +declare+: the player's choices as
  # [[step key, value], ...] in builder order. +names+: combatant id →
  # display name. +dm_started+: created by the DM's builder (no request).
  def initialize(turn_key:, blob:, kind: 'attack', actor_id: nil, actor_name: nil, declare: nil, summary: nil,
                 pool_cost: nil, ability: nil, names: {}, dm_started: false,
                 attacker_id: nil, attacker_name: nil, target_id: nil, action_value: nil, category: nil)
    raise ArgumentError, "unknown kind #{kind}" unless KINDS.include?(kind.to_s)
    # The action's time (main / bonus / free / minute): which ones count as Main Actions.
    @category = (category || (kind.to_s == 'attack' ? 'main' : nil))&.to_s
    @id          = SecureRandom.hex(5)
    @kind        = kind.to_s
    @actor_id    = actor_id || attacker_id
    @actor_name  = actor_name || attacker_name
    @turn_key    = turn_key
    @blob        = blob
    @ability     = ability
    @names       = names
    @choices     = {}
    @tasks       = []
    @rolls       = {}
    @status      = 'active'
    @created_at  = Time.now.to_i
    @dm_started  = dm_started
    @pool_cost   = pool_cost
    @needs_open  = false
    @last_sync   = nil
    @live_label  = nil
    @live_target = nil
    @reaction_used = Set.new
    if dm_started
      @declare = []
      @stage = 'builder'
    else
      @declare = declare || [['target', target_id.to_s], ['action', action_value.to_s]]
      @declare = @declare.map { |k, v| [k.to_s, v.to_s] }
      @stage = 'declare'
      decl = new_task('declare', 'declare', @actor_id, 'kind' => 'declare')
      decl.merge!('status' => 'submitted', 'by' => 'player', 'value' => @declare,
                  'summary' => summary || declare_summary)
    end
  end

  def dm_started? = @dm_started
  def attacker_id = @actor_id
  def attacker_name = @actor_name

  # --- Queries ------------------------------------------------------------------

  # Combat Pool the declared action will cost when the DM commits it.
  def declared_pool_cost
    return @pool_cost.to_i unless @pool_cost.nil?
    return 0 if @dm_started
    action = @declare.to_h['action'].to_s
    opt = raw_options('action').find { |o| o[:value].to_s == action }
    speed = Array(opt && opt.dig(:patch, :set_speed)).first&.dig(:speed).to_i
    speed + action.split('|').last.to_i
  end

  def summary
    d = stage_tasks('declare').first
    return d['summary'] if d
    [action_name, target_id && "at #{name_of(target_id)}"].compact.join(' ')
  end

  # The action's own name, without dice or target: "Fire Dart", "+1 Rapier",
  # "Bardic Inspiration".
  def action_name
    d = @declare.to_h.merge(@choices)
    # An attack reads by its weapon type ("Great Sword", not "+2 Vicious
    # Great sword"): the action's value is "<weapon type>|<dice>".
    if @kind == 'attack' && (type = d['action'].to_s.split('|').first.to_s) != '' && type != 'spiritual_weapon'
      return type.split(/[\s_]+/).map(&:capitalize).join(' ')
    end
    return @live_label.to_s if @dm_started || @declare.empty?
    case @kind
    when 'attack'
      opt = raw_options('action').find { |o| o[:value].to_s == d['action'] }
      clean(opt ? (opt[:summary] || opt[:label]) : d['action']).split(' — ').first
    when 'special' then @ability.to_s
    else
      opt = raw_options('spell').find { |o| o[:value].to_s == d['spell'] }
      opt ? clean(opt[:summary] || opt[:label]) : d['spell'].to_s
    end
  end

  # The roll prompt's header, from the viewer's side: "Casting Fire Dart"
  # for the actor, "Ash Windmere casting Fire Dart at you" for a target.
  def headline(viewer_ids)
    gerund = { 'attack' => 'Attacking with', 'cast' => 'Casting', 'item' => 'Using', 'special' => 'Using' }[@kind]
    return "#{gerund} #{action_name}" + (target_id ? " at #{name_of(target_id)}" : '') if viewer_ids.include?(@actor_id)
    at = if target_id.nil? then ''
         elsif viewer_ids.include?(target_id) then ' at you'
         else " at #{name_of(target_id)}"
         end
    "#{@actor_name} #{gerund.downcase} #{action_name}#{at}"
  end

  # The action in a line for a prompt, from the viewer's side:
  # "Garroth Vask Attacks Wolf with Great Sword", "Ash Casts Fire Dart at You".
  def title_line(viewer_ids)
    actor = viewer_ids.include?(@actor_id) ? 'You' : @actor_name.to_s
    tgt = if target_id.nil? then nil
          elsif viewer_ids.include?(target_id) then 'You'
          else name_of(target_id)
          end
    case @kind
    when 'attack' then "#{actor} Attack#{actor == 'You' ? '' : 's'} #{tgt || 'a target'} with #{action_name}"
    when 'cast' then "#{actor} Cast#{actor == 'You' ? '' : 's'} #{action_name}#{tgt ? " at #{tgt}" : ''}"
    else "#{actor} Use#{actor == 'You' ? '' : 's'} #{action_name}#{tgt ? " on #{tgt}" : ''}"
    end
  end

  # Whether this action holds up the actor's other actions while it is in
  # progress. An Attack always does; a Spell / Item when it rolls a check; a
  # Special when it has a builder. A buff, a Reservoir pour or Rage does not.
  def blocking?
    return true if @dm_started
    case @kind
    when 'attack' then true
    when 'special' then !@blob.nil?
    else
      spell = raw_options('spell').find { |o| o[:value].to_s == @declare.to_h['spell'].to_s }
      !!(spell && spell[:cast] && spell[:cast][:roll])
    end
  end

  # The builder synced recently (open and on screen on the DM's page).
  def live? = @stage == 'builder' && !@last_sync.nil? && !@page_left && Time.now.to_f - @last_sync < STALE_SECONDS

  # The DM left the Encounter page: the builder is closed, but the action
  # (its choices, the phones' prompts and dice) stays until the DM is back.
  def page_left! = @page_left = true

  def task(task_id) = @tasks.find { |t| t['id'] == task_id.to_s }
  def stage_tasks(stage = @stage) = @tasks.select { |t| t['stage'] == stage }
  def roll_tasks = @tasks.select { |t| t['kind'] == 'roll' }
  def choice_tasks = @tasks.select { |t| t['kind'] == 'choice' }
  def open_tasks = @tasks.select { |t| t['status'] != 'approved' && t['stage'] == @stage }
  def active? = @status == 'active'

  # The targeted Combatant, or nil (no target, an object, or an area).
  def target_id
    t = @live_target || @choices['target'] || @declare.to_h['target']
    t.to_s.match?(/\A\d+\z/) ? t.to_i : nil
  end

  def name_of(cid) = cid.nil? ? 'DM' : (@names[cid.to_i] || "Combatant ##{cid}")

  # A choice task's options, for the phone: a flat list of
  # { value, label, summary, group, group_label, dice, disabled }.
  def options_for(t) = Array(t['options'])

  # Every Roll of the action as the DM's builder has it.
  def roll_overview
    roll_tasks.map do |t|
      r = t['roll']
      v = t['value'] || {}
      { task_id: t['id'], owner: t['owner_name'], owner_id: t['owner_id'], name: r['name'],
        what: r['what'], bonus: r['bonus'].to_i, dice_count: r['dice_count'], tn: r['tn'],
        starting_value: r['starting_value'], positive_reroll: r['positive_reroll'], negative_reroll: r['negative_reroll'],
        failure_modifier: r.fetch('failure_modifier', -1),
        rider: r['roll_id'].to_s.start_with?('rider-'), # a weapon's Damage Rider (e.g. Vicious)
        status: t['status'], summary: t['summary'], claimed: !!t['claimed'], by: t['by'],
        dice: v['dice'], rerolled: v['rerolled'], final: v['final'], successes: v['successes'] }
    end
  end

  # A Roll a phone may see: shared by the DM (approved), or the viewer's own
  # roll they just made. Anything else — a DM roll, or another player's roll,
  # not yet approved — looks exactly like a Roll nobody has rolled.
  def visible_to?(t, viewer_ids)
    t['status'] == 'approved' || (t['by'] == 'player' && viewer_ids.include?(t['owner_id']))
  end

  def public_roll_overview(viewer_ids = [])
    roll_tasks.zip(roll_overview).map do |t, r|
      next r if visible_to?(t, viewer_ids)
      r.merge(status: 'waiting', summary: nil, by: nil, dice: nil, rerolled: nil, final: nil, successes: nil)
    end
  end

  # A roll the DM made for its owner and has not approved: the owner still
  # sees their Roll button (their own roll would replace it).
  def dm_pending?(t) = t['kind'] == 'roll' && t['status'] == 'submitted' && t['by'] == 'dm'

  # --- The builder (DM's page) ------------------------------------------------------

  # Mirror the builder's state. +s+ (string keys): choices, target_id,
  # action_label, idle, step { key, options [...], luck {...} }, rolls [...].
  # +claimed+: ->(combatant_id) { true when that Combatant is a player with a phone }.
  def sync!(s, claimed:)
    @last_sync = Time.now.to_f
    @page_left = false
    @needs_open = false
    @stage = 'builder' if @stage == 'declare'
    @choices = (s['choices'] || {}).to_h { |k, v| [k.to_s, v.to_s] }
    @live_target = s['target_id'] if s.key?('target_id')
    @live_label = s['action_label'].to_s unless s['action_label'].to_s.empty?
    @ability ||= @live_label if @kind == 'special' # a DM-started Ability: which one, for resuming
    # A Luck answer uses that player's reaction for this action.
    choice_tasks.each do |t|
      next unless t['step'].start_with?('luck:') && t['owner_id']
      v = @choices[t['step']] || t['value']
      @reaction_used << t['owner_id'] if v && !v.to_s.end_with?('|none')
    end
    # Reactions (Kesser's Gambit) are not builder steps: they stay.
    keep = @tasks.select { |t| t['kind'] == 'declare' || reaction_task?(t) }
    unless s['idle']
      step = s['step']
      if step.is_a?(Hash) && step['key'].to_s.match?(PLAYER_STEPS)
        owner = step_owner(step)
        if owner && claimed.call(owner)
          key = step['key'].to_s
          t = choice_tasks.find { |x| x['step'] == key && x['owner_id'] == owner } ||
              new_task('builder', key, owner, 'kind' => 'choice')
          t['options'] = step['luck'] ? luck_options(step['luck']) : normalize_options(step['options'])
          if step['luck'] && @reaction_used.include?(owner)
            t['options'] = t['options'].map { |o| o[:group] == 'none' ? o : o.merge(disabled: true) }
          end
          t['luck_amount'] = step.dig('luck', 'source', 'amount')&.to_i
          keep << t
        end
      end
      Array(s['rolls']).each { |r| keep << sync_roll(r, claimed) } if s['rolls'].is_a?(Array)
    end
    @tasks.replace(keep)
  end

  # The builder is still open (it fetched where things stand).
  def touch!
    @last_sync = Time.now.to_f
    @page_left = false
  end

  # What the builder needs back: a player's answer to the step it is on, and
  # where every Roll stands (claimed ones with their dice, for the DM only).
  def builder_view
    answer = choice_tasks.find { |t| t['status'] == 'submitted' && !reaction_task?(t) }
    asked = choice_tasks.reject { |t| reaction_task?(t) }.first
    { flow_id: @id, stage: @stage, status: @status,
      answer: answer && { step: answer['step'], value: answer['value'] },
      waiting_on: asked && asked['status'] == 'waiting' && !reaction_task?(asked) ? asked['owner_name'] : nil,
      reactions: reactions_view,
      rolls: roll_tasks.to_h do |t|
        v = t['value'] || {}
        [t['roll']['roll_id'], { task_id: t['id'], claimed: !!t['claimed'], owner: t['owner_name'],
                                 fudge: t['fudge'] || 'none',
                                 status: t['status'], by: t['by'], dice: v['dice'], rerolled: v['rerolled'],
                                 final: v['final'], successes: v['successes'], crits: v['crits'] }]
      end }
  end

  # Confirm in the builder: every claimed Roll with dice is approved, and the
  # unclaimed Rolls the builder rolled (+rolls+: { roll_id => { dice,
  # rerolled, final } }) are scored and shared.
  # When the DM last shared the Rolls (Confirm), and how many times: every
  # phone in combat shows them then (the dice thrown as if just rolled).
  attr_reader :shared_at, :shared_version

  def share!(rolls = {})
    @shared_at = Time.now.to_f
    @shared_version = @shared_version.to_i + 1
    roll_tasks.each do |t|
      rid = t['roll']['roll_id']
      if t['claimed']
        t['status'] = 'approved' if t['value']
      elsif (v = rolls[rid] || rolls[rid.to_sym])
        t['value'] = score_roll(t, v)
        t['summary'] = roll_summary(t['value'])
        t.merge!('status' => 'approved', 'by' => 'dm')
      end
    end
  end

  # --- Reactions (Kesser's Gambit) ---------------------------------------------------

  # Each Combatant has one reaction per action by another creature; Luck on
  # this action uses it too.
  def reaction_used?(cid) = @reaction_used.include?(cid)
  def reaction_offered?(cid) = @tasks.any? { |t| t['step'] == "reaction:#{cid}" }
  def reaction_task?(t) = t['step'].start_with?('reaction:', 'roll:gambit-')

  # Offer a Roll Table reaction to +cid+'s phone. +dice+: the dice counts it may
  # channel with; +roll+: the Channel check's spec without dice_count.
  def offer_reaction(cid, ability:, mana_cost:, dice:, roll:)
    opts = [{ value: 'none', label: 'No reaction', summary: 'No reaction', group: 'none', group_label: 'No reaction',
              dice: nil, disabled: false }]
    dice.each do |n|
      opts << { value: "gambit|#{n}", label: n.to_s, summary: "#{ability} \u2014 #{n} dice (#{mana_cost} mana)",
                group: 'gambit', group_label: ability, dice: n, disabled: false }
    end
    new_task('builder', "reaction:#{cid}", cid, 'kind' => 'choice', 'options' => opts,
             'reaction' => { 'ability' => ability, 'mana_cost' => mana_cost, 'roll' => roll })
  end

  # The DM's view of the reactions: who, with how many dice, and their Channel check.
  def reactions_view
    @tasks.select { |t| t['step'].start_with?('reaction:') && t['value'].to_s.start_with?('gambit|') }.map do |t|
      cid = t['owner_id']
      r = @tasks.find { |x| x['step'] == "roll:gambit-#{cid}" }
      v = (r && r['value']) || {}
      { combatant_id: cid, owner: t['owner_name'], ability: t.dig('reaction', 'ability'),
        dice: t['value'].split('|').last.to_i, rolled: !v['final'].nil?, successes: v['successes'], final: v['final'],
        tn: r && r.dig('roll', 'tn'), starting_value: r && r.dig('roll', 'starting_value') }
    end
  end

  # --- Answers ----------------------------------------------------------------------

  # A player answers their own task. A choice waits for the builder to pick
  # it; a roll waits for the DM's approval (and replaces a DM roll not yet
  # approved).
  def submit(task_id, value, by: 'player')
    t = task(task_id) or raise ArgumentError, 'unknown task'
    raise ArgumentError, 'that step is finished' if t['status'] == 'approved' || t['stage'] != @stage
    return answer_reaction(t, value) if t['step'].start_with?('reaction:')
    if t['kind'] == 'roll'
      t['value'] = score_roll(t, value)
      t['summary'] = roll_summary(t['value'])
    else
      opt = options_for(t).find { |o| o[:value].to_s == value.to_s }
      raise ArgumentError, 'not one of the options' unless opt
      raise ArgumentError, 'that option is not available' if opt[:disabled]
      t['value'] = value.to_s
      t['summary'] = opt[:summary]
    end
    t['status'] = 'submitted'
    t['by'] = by
    t
  end

  # The fudge for a roll still to be rolled on a phone. Raises when it is
  # unknown or the roll is already in.
  def set_fudge(task_id, fudge)
    t = task(task_id) or raise ArgumentError, 'unknown task'
    raise ArgumentError, 'not a roll' unless t['kind'] == 'roll'
    raise ArgumentError, 'unknown fudge' unless FUDGES.include?(fudge.to_s)
    raise ArgumentError, 'already rolled' if t['by'] == 'player' || t['status'] == 'approved'
    t['fudge'] = fudge.to_s == 'none' ? nil : fudge.to_s
    t
  end

  # The fudge chosen when the DM approved the request: for the requester's
  # own roll once the builder brings it up.
  def request_fudge=(fudge)
    @request_fudge = FUDGES.include?(fudge.to_s) && fudge.to_s != 'none' ? fudge.to_s : nil
  end

  # DM approves: the player's request (opens the builder), or a roll (shares it).
  def approve(task_id)
    t = task(task_id) or raise ArgumentError, 'unknown task'
    raise ArgumentError, 'nothing to approve yet' unless t['status'] == 'submitted'
    t['status'] = 'approved'
    if t['kind'] == 'declare'
      @declare.each { |k, v| @choices[k] = v }
      @stage = 'builder'
      @needs_open = true
    end
    t
  end

  # DM sends a submitted roll back to its owner to roll again.
  def reject(task_id)
    t = task(task_id) or raise ArgumentError, 'unknown task'
    raise ArgumentError, 'nothing to send back' unless t['status'] == 'submitted'
    raise ArgumentError, 'the request itself cannot be sent back; cancel it instead' if t['kind'] == 'declare'
    t.merge!('status' => 'waiting', 'value' => nil, 'summary' => nil, 'by' => nil)
    t
  end

  # DM rolls a Roll on the owner's behalf (server-side dice), for the DM's
  # eyes only until approved. May be repeated as often as the DM likes.
  def roll_for(task_id, rng: Random.new)
    t = task(task_id) or raise ArgumentError, 'unknown task'
    raise ArgumentError, 'not a roll' unless t['kind'] == 'roll'
    r = t['roll']
    initial = Array.new(r['dice_count']) { rng.rand(1..die_size) }
    final, rerolled = ActionFlow.apply_rerolls(initial, r['tn'], r['positive_reroll'].to_i, r['negative_reroll'].to_i, rng)
    submit(task_id, { 'dice' => initial, 'rerolled' => rerolled, 'final' => final }, by: 'dm')
  end

  def cancel! = @status = 'cancelled'

  # The DM committed it. +outcome+: what happened, in a line for every phone
  # ("Garroth Vask hit Wolf with Great Sword for 7 slashing damage").
  def done!(outcome = nil)
    @status = 'done'
    @outcome = outcome.to_s.empty? ? "#{@actor_name}: #{summary}" : outcome.to_s
    @finished_at = Time.now.to_f
  end
  attr_reader :outcome, :finished_at

  # For opening the builder: every choice the builder had made, in the order
  # it made them (it reports them as it goes), so coming back to the
  # Encounter page picks up where the DM left off; before the builder ever
  # ran, the player's request in builder step order.
  def prefill
    choices =
      if @choices.any? && @stage == 'builder' && !@last_sync.nil?
        @choices.to_a
      else
        order = Array(@blob && @blob[:steps]).map { |s| s[:key].to_s }
        decl = @declare.to_h
        order.filter_map { |k| [k, decl[k]] if decl.key?(k) }
      end
    {
      flow_id: @id, kind: @kind, ability: @ability, attacker_id: @actor_id, actor_id: @actor_id,
      resumed: !@last_sync.nil?, choices: choices, rolls: {}
    }
  end

  # --- Dice (shared with the phone's rules) -----------------------------------------

  def self.die_size = DiceResolution.config.die_size

  # Luck rerolls (dice_resolution_design.md → Reroll): a positive reroll
  # rerolls up to +count+ non-Successes, lowest first; a negative reroll up to
  # +count+ Successes, highest first. Each die is rerolled at most once.
  # Returns [final, rerolled] where rerolled[i] is the new value or nil.
  def self.apply_rerolls(dice, tn, positive, negative, rng = Random.new)
    final = dice.dup
    rerolled = Array.new(dice.length)
    pick = lambda do |count, eligible, order|
      idx = dice.each_index.select { |i| eligible.call(dice[i]) && rerolled[i].nil? }
      idx = idx.sort_by { |i| [order * dice[i], i] }
      idx.first(count).each { |i| final[i] = rerolled[i] = rng.rand(1..die_size) }
    end
    pick.call(negative, ->(v) { v >= tn }, -1) if negative.positive?
    pick.call(positive, ->(v) { v < tn }, 1) if positive.positive?
    [final, rerolled]
  end

  # +failure_modifier+: what a 1 counts for (−1; 0 for a Damage Rider, whose
  # 1s never take damage away).
  def self.dois(final, tn, starting_value, failure_modifier = -1)
    size = die_size
    starting_value.to_i + final.sum do |v|
      if v == size then 2
      elsif v == 1 then failure_modifier.to_i
      elsif v >= tn then 1
      else 0
      end
    end
  end

  private

  def die_size = ActionFlow.die_size

  # A reaction offer answered: "none", or "gambit|N" → the Channel check is theirs to roll.
  def answer_reaction(t, value)
    opt = options_for(t).find { |o| o[:value].to_s == value.to_s }
    raise ArgumentError, 'not one of the options' unless opt
    raise ArgumentError, 'your reaction is already used on this action' if value != 'none' && reaction_used?(t['owner_id'])
    t.merge!('value' => value.to_s, 'summary' => opt[:summary], 'status' => 'approved', 'by' => 'player')
    return t if value == 'none'
    cid = t['owner_id']
    @reaction_used << cid
    spec = t.dig('reaction', 'roll').merge('roll_id' => "gambit-#{cid}", 'dice_count' => value.split('|').last.to_i)
    new_task('builder', "roll:gambit-#{cid}", cid, 'kind' => 'roll', 'roll' => spec, 'claimed' => true)
    t
  end

  def new_task(stage, step, owner_id, extra = {})
    t = { 'id' => SecureRandom.hex(4), 'stage' => stage, 'step' => step, 'kind' => 'choice',
          'owner_id' => owner_id, 'owner_name' => name_of(owner_id),
          'status' => 'waiting', 'value' => nil, 'summary' => nil, 'by' => nil }.merge(extra)
    @tasks << t
    t
  end

  # Who answers a player step: the target defends, the shielding ally
  # interposes, a Luck source spends its Luck (nil for the DM's own Luck).
  def step_owner(step)
    case step['key'].to_s
    when 'defense' then target_id
    when 'ally_defense' then shield_caster(Array(step['options']).map { |o| o['value'].to_s })
    else
      id = step.dig('luck', 'source', 'id')
      id.nil? ? nil : id.to_i
    end
  end

  def shield_caster(values)
    v = values.find { |x| x.start_with?('shield:') }
    v && v.split('|').first.split(':').last.to_i
  end

  # Who rolls a Roll of the builder.
  def roll_owner(r)
    id = r['id'].to_s
    case id
    when 'attacker', 'caster', 'performance' then @actor_id
    when 'defender', 'target' then target_id
    when 'shield' then shield_caster([@choices['ally_defense'].to_s])
    when 'enchant' then @actor_id # a weapon's +X extra dice, rolled with the attack
    when /\Arider-/ then @actor_id # a weapon's Damage Rider: the attacker's dice, once the hit lands
    when /\Asave-(\d+)\z/ then Regexp.last_match(1).to_i
    else r['owner_id']&.to_i
    end
  end

  def sync_roll(r, claimed)
    rid = r['id'].to_s
    owner = roll_owner(r)
    rider = rid.start_with?('rider-')
    spec = { 'roll_id' => rid, 'name' => (rider ? r['creature_name'] : r['roll_name']).to_s, 'creature_name' => r['creature_name'].to_s,
             'dice_count' => r['dice_count'].to_i, 'tn' => r['tn'].to_i, 'starting_value' => r['starting_value'].to_i,
             'positive_reroll' => r['positive_reroll'].to_i, 'negative_reroll' => r['negative_reroll'].to_i,
             'speed' => r['speed'].to_i, 'side' => r['side'].to_s,
             # For the roll prompt: what is rolled in words and its own bonus,
             # e.g. "Arcana" +3, "Dodging" +2, "Wisdom save" +1.
             'what' => roll_what(r), 'bonus' => competency_of(r['bonus_penalty_list']),
             'failure_modifier' => r.key?('failure_modifier') && !r['failure_modifier'].nil? ? r['failure_modifier'].to_i : -1 }
    t = roll_tasks.find { |x| x['roll']['roll_id'] == rid } ||
        new_task('builder', "roll:#{rid}", owner, 'kind' => 'roll', 'roll' => spec)
    # The dice or TN changed under it (the DM changed a step): roll again.
    same = %w[dice_count tn starting_value positive_reroll negative_reroll].all? { |k| t['roll'][k] == spec[k] }
    t.merge!('status' => 'waiting', 'value' => nil, 'summary' => nil, 'by' => nil) unless same && t['owner_id'] == owner
    t.merge!('roll' => spec, 'owner_id' => owner, 'owner_name' => owner ? name_of(owner) : r['creature_name'].to_s,
             'claimed' => !owner.nil? && claimed.call(owner))
    # The fudge chosen with the request applies to the requester's own roll.
    t['fudge'] ||= @request_fudge if @request_fudge && owner == @actor_id && %w[attacker caster performance].include?(rid)
    t
  end

  def step_def(key) = Array(@blob && @blob[:steps]).find { |s| s[:key].to_s == key }

  # Options of a step of the request's builder blob under the declared choices.
  def raw_options(key)
    step = step_def(key) or return []
    return Array(step[:options]) if step[:options]
    return [] unless step[:options_by]
    map_key = Array(step[:options_by]).map { |s| choice_key(s.to_s) }.join('|')
    Array((step[:options_map] || {})[map_key] || (step[:options_map] || {})[map_key.to_sym])
  end

  def choice_key(step_key)
    v = @declare.to_h[step_key]
    return '' if v.nil?
    opt = raw_options(step_key).find { |o| o[:value].to_s == v.to_s }
    (opt && !opt[:key].nil? ? opt[:key] : v).to_s
  end

  def clean(label) = CGI.unescapeHTML(label.to_s.gsub(/<[^>]*>/, '')).strip

  # The builder's options for a step as the phone shows them: grouped (one
  # group per defense, its dice counts ascending), info text dropped.
  def normalize_options(list)
    seen = {}
    groups = []
    opts = Array(list).filter_map do |o|
      o = o.transform_keys(&:to_s)
      next if o['kind'] == 'info'
      v = o['value'].to_s
      next if v.empty? || seen[v]
      seen[v] = true
      head, dice = v.split('|', 2)
      dice_n = dice.to_s.match?(/\A\d+\z/) ? dice.to_i : nil
      summary = clean(o['summary'] || o['label'])
      group = (o['group'] || head).to_s
      groups << group unless groups.include?(group)
      { value: v, label: clean(o['label']), summary: summary,
        group: group, group_label: summary.split(' — ').first.to_s,
        dice: dice_n, disabled: !!o['disabled'] }
    end
    opts.sort_by { |o| [groups.index(o[:group]), o[:dice] || 0] }
  end

  # A Luck step's options from the builder's table: { source { sid, label,
  # penalty }, targets [{ roll_id, label, cap }] }.
  def luck_options(luck)
    src = luck['source'] || {}
    sid = src['sid'].to_s
    out = [{ value: "#{sid}|none", label: 'No luck', summary: "#{src['label']}: no luck", group: 'none',
             group_label: 'No luck', dice: nil, disabled: false }]
    Array(luck['targets']).each do |tgt|
      rid = tgt['roll_id'].to_s
      cap = tgt['cap'].to_i
      next unless cap.positive?
      who = tgt['label'].to_s
      dice = ->(n) { "#{n} #{n == 1 ? 'die' : 'dice'}" }
      (1..cap).each do |n|
        out << { value: "#{sid}|pos|#{n}|#{rid}", label: "+#{n}", summary: "Help #{who} \u2014 reroll #{dice.call(n)}",
                 group: "pos:#{rid}", group_label: "Help #{who}", dice: n, disabled: false, tone: 'help' }
      end
      next unless src['penalty']
      (1..cap).each do |n|
        out << { value: "#{sid}|neg|#{n}|#{rid}", label: "−#{n}", summary: "Hinder #{who} \u2014 reroll #{dice.call(n)}",
                 group: "neg:#{rid}", group_label: "Hinder #{who}", dice: n, disabled: false, tone: 'hinder' }
      end
    end
    out
  end

  # What a Roll is, in words, for the roll prompt: the actor's skill
  # ("Martial", "Arcana", "Perform (Dance)", the Ability), or the defense as
  # a verb ("Dodging", "Blocking", "Parrying with Rapier", "Wisdom save").
  def roll_what(r)
    c = @declare.to_h.merge(@choices)
    case r['id'].to_s
    when /\Arider-/ then r['creature_name'].to_s # "Vicious"
    when 'attacker' then 'Martial'
    when 'caster'
      skill = c['dice'].to_s.split('|')[1].to_s
      skill.empty? ? r['roll_name'].to_s.delete('()') : pretty_skill(skill)
    when 'performance'
      perf = c['performance']
      perf ? pretty_skill(perf) : (@ability || r['roll_name']).to_s
    else
      name = r['roll_name'].to_s.delete('()').strip
      case name
      when 'Dodge' then 'Dodging'
      when 'Block' then 'Blocking'
      when /\AParry with (.+)\z/ then "Parrying with #{Regexp.last_match(1)}"
      when /\ARing of Parry/ then 'Parrying (Ring of Parry)'
      else name
      end
    end
  end

  def pretty_skill(key)
    return '' if key.empty?
    family, *rest = key.split('_')
    return "#{family.capitalize} (#{rest.map(&:capitalize).join(' ')})" if %w[perform craft profession game].include?(family) && rest.any?
    key.split('_').map(&:capitalize).join(' ')
  end

  # The Roll's own Competency bonus (before anything crosses from the other side).
  def competency_of(list)
    entry = Array(list).find { |type, _| type.to_s == 'Competency' }
    entry ? entry[1].to_i : 0
  end

  # The attack's request in words; other kinds pass their own summary.
  def declare_summary
    d = @declare.to_h
    opt = raw_options('action').find { |o| o[:value].to_s == d['action'] }
    "#{opt ? clean(opt[:summary] || opt[:label]) : d['action']} at #{name_of(d['target'].to_i)}"
  end

  # Check a roll answer and score it on the server (the phone's own total is not trusted).
  def score_roll(t, value)
    v = value.is_a?(Hash) ? value.transform_keys(&:to_s) : {}
    r = t['roll']
    dice = Array(v['dice']).map(&:to_i)
    final = Array(v['final'] || dice).map(&:to_i)
    rerolled = Array(v['rerolled'] || Array.new(dice.length)).map { |x| x.nil? ? nil : x.to_i }
    raise ArgumentError, "expected #{r['dice_count']} dice" unless dice.length == r['dice_count'] && final.length == dice.length
    raise ArgumentError, 'dice out of range' unless (dice + final).all? { |d| d.between?(1, die_size) }
    successes = ActionFlow.dois(final, r['tn'], r['starting_value'], r.fetch('failure_modifier', -1))
    crits = final.count(die_size)
    @rolls[r['roll_id']] = { 'successes' => successes, 'crits' => crits, 'final' => final,
                             'tn' => r['tn'], 'starting_value' => r['starting_value'] }
    { 'dice' => dice, 'rerolled' => rerolled, 'final' => final, 'successes' => successes, 'crits' => crits }
  end

  def roll_summary(v)
    word = v['successes'].abs == 1 ? 'success' : 'successes'
    "#{v['final'].sort.reverse.join(' ')} → #{v['successes']} #{word}#{v['crits'].positive? ? ", #{v['crits']} crit" : ''}"
  end
end

# In-memory store of the flows in progress (cleared by a server restart).
class ActionFlows
  def self.instance = (@instance ||= new)
  def self.instance=(store)
    @instance = store
  end

  def initialize
    @flows = []
    @mutex = Mutex.new
  end

  def add(flow) = @mutex.synchronize { @flows << flow; flow }
  def find(id) = @mutex.synchronize { @flows.find { |f| f.id == id.to_s } }
  def active = @mutex.synchronize { @flows.select(&:active?) }
  # Not cancelled, with Rolls shared in the last +seconds+ (done ones too: a
  # commit right after Confirm must not hide them).
  # Committed in the last +seconds+: what happened, for every phone.
  def recent_done(seconds = 120)
    now = Time.now.to_f
    @mutex.synchronize { @flows.select { |f| f.status == 'done' && f.finished_at && now - f.finished_at < seconds } }
  end

  def recent_shared(seconds = 120)
    now = Time.now.to_f
    @mutex.synchronize { @flows.select { |f| f.status != 'cancelled' && f.shared_at && now - f.shared_at < seconds } }
  end
  def synchronize(&block) = @mutex.synchronize(&block)
  def clear! = @mutex.synchronize { @flows.clear }
end
