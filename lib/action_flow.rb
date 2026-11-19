require 'securerandom'
require 'cgi'

# A player-driven action (docs/project/action_flow.md): an Attack, a Cast, an
# Item, or a Special Ability. The actor asks for it from the Android app;
# every Combatant with a choice to make answers on their own phone; each
# answer waits for the DM's approval; dice are rolled on the phones; and the
# DM finishes it in the normal builder (Attack / Cast / Item / Special pane).
#
# The flow is built on the DM's own Action Builder blob for that action
# (attack_builder_blob, cast_builder_blob, item_builder_blob,
# special_builder_blob), so every option, cost and patch is exactly what the
# DM would see. A Special without a builder (e.g. Rage) has no blob: it is
# declared, approved, and confirmed by the DM. Stages, in order:
#
#   declare  — the actor's choices (Target, Weapon / Spell & dice…): the request.
#   respond  — at the same time: the target's Defense, and an ally's Shield
#              (when the target is shielded). A Saving Throw is not a choice
#              (always the full Dice Cap), so it is applied without asking.
#   luck     — at the same time: one task per Luck source (a Bard's Bardic
#              Inspiration, DM Luck). After respond, because how much Luck a
#              Roll can take depends on its dice (the builder's order too).
#   roll     — at the same time: one roll per Roll in play (attacker / caster /
#              performer, defender / target, ally shield), with Luck folded in.
#   resolve  — the DM opens the builder pre-filled and commits it.
#
# Skipped straight to resolve: a Spell that rolls nothing (a buff, a Reservoir
# pour), an area Spell (the DM places it on the map, and the creatures caught
# in it are only known then), and a Special with no builder.
#
# A task belongs to one Combatant (owner_id), or to the DM alone (owner_id nil
# — e.g. DM Luck). The DM may answer any task on the owner's behalf; that
# approves it at once and clears it from the owner's phone.
class ActionFlow
  STAGES = %w[declare respond luck roll resolve].freeze

  KINDS = %w[attack cast item special].freeze

  attr_reader :id, :kind, :actor_id, :actor_name, :turn_key, :blob, :choices, :tasks, :rolls, :created_at, :ability
  attr_accessor :stage, :status

  # +kind+: attack / cast / item / special. +blob+: the builder blob (symbol
  # keys), or nil for a Special with no builder. +declare+: the actor's
  # choices as [[step key, value], ...] in builder order. +names+: combatant
  # id → display name. The attack form (target_id + action_value) is kept for
  # callers that predate the other kinds. The declare task starts submitted.
  def initialize(turn_key:, blob:, kind: 'attack', actor_id: nil, actor_name: nil, declare: nil, summary: nil,
                 pool_cost: nil, ability: nil, names: {},
                 attacker_id: nil, attacker_name: nil, target_id: nil, action_value: nil)
    raise ArgumentError, "unknown kind #{kind}" unless KINDS.include?(kind.to_s)
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
    @stage       = 'declare'
    @status      = 'active'
    @created_at  = Time.now.to_i
    @declare     = declare || [['target', target_id.to_s], ['action', action_value.to_s]]
    @declare     = @declare.map { |k, v| [k.to_s, v.to_s] }
    @pool_cost   = pool_cost
    decl = new_task('declare', 'declare', @actor_id)
    decl.merge!('status' => 'submitted', 'by' => 'player', 'value' => @declare,
                'summary' => summary || declare_summary)
  end

  # The names the attack-only callers (and the DM panel) use.
  def attacker_id = @actor_id
  def attacker_name = @actor_name

  # --- Queries ------------------------------------------------------------------

  # Combat Pool the declared action will cost when the DM commits it. For an
  # attack: the weapon's Speed plus one per die (from the chosen action's
  # patch); other kinds are given it by the caller.
  def declared_pool_cost
    return @pool_cost.to_i unless @pool_cost.nil?
    action = @declare.to_h['action'].to_s
    opt = raw_options('action').find { |o| o[:value].to_s == action }
    speed = Array(opt && opt.dig(:patch, :set_speed)).first&.dig(:speed).to_i
    speed + action.split('|').last.to_i
  end

  def summary = stage_tasks('declare').first['summary']

  def task(task_id) = @tasks.find { |t| t['id'] == task_id.to_s }
  def stage_tasks(stage = @stage) = @tasks.select { |t| t['stage'] == stage }
  def open_tasks = @tasks.select { |t| t['status'] != 'approved' && t['stage'] == @stage }
  def active? = @status == 'active'
  # The targeted Combatant, or nil (no target, an object, or an area).
  def target_id
    t = @choices['target'] || @declare.to_h['target']
    t.to_s.match?(/\A\d+\z/) ? t.to_i : nil
  end
  def name_of(cid) = cid.nil? ? 'DM' : (@names[cid.to_i] || "Combatant ##{cid}")

  # Options for a respond task, for the phone and the DM's picker: a flat list
  # of { value, label, group, group_label, dice, disabled }.
  def options_for(t)
    case t['step']
    when 'defense'      then step_options('defense')
    when 'ally_defense' then step_options('ally_defense')
    when /\Aluck:/      then luck_options(t['step'])
    else []
    end
  end

  # --- Answers ----------------------------------------------------------------------

  # A player answers their own task (submitted; waits for the DM).
  def submit(task_id, value, by: 'player')
    t = task(task_id) or raise ArgumentError, 'unknown task'
    raise ArgumentError, 'that step is finished' if t['status'] == 'approved' || t['stage'] != @stage
    if t['kind'] == 'roll'
      t['value'] = score_roll(t, value)
      t['summary'] = roll_summary(t['value'])
    else
      opt = options_for(t).find { |o| o[:value] == value.to_s }
      raise ArgumentError, 'not one of the options' unless opt
      raise ArgumentError, 'that option is not available' if opt[:disabled]
      t['value'] = value.to_s
      t['summary'] = opt[:summary]
    end
    t['status'] = 'submitted'
    t['by'] = by
    t
  end

  # DM approves a submitted task. Advances the stage when it was the last one.
  def approve(task_id)
    t = task(task_id) or raise ArgumentError, 'unknown task'
    raise ArgumentError, 'nothing to approve yet' unless t['status'] == 'submitted'
    t['status'] = 'approved'
    advance! if open_tasks.empty?
    t
  end

  # DM sends a submitted task back to its owner to answer again.
  def reject(task_id)
    t = task(task_id) or raise ArgumentError, 'unknown task'
    raise ArgumentError, 'nothing to send back' unless t['status'] == 'submitted'
    raise ArgumentError, 'the request itself cannot be sent back; cancel it instead' if t['kind'] == 'declare'
    t.merge!('status' => 'waiting', 'value' => nil, 'summary' => nil, 'by' => nil)
    t
  end

  # DM answers on the owner's behalf: recorded and approved at once.
  def decide(task_id, value)
    submit(task_id, value, by: 'dm')
    approve(task_id)
  end

  # DM rolls a roll task on the owner's behalf (server-side dice).
  def roll_for(task_id, rng: Random.new)
    t = task(task_id) or raise ArgumentError, 'unknown task'
    raise ArgumentError, 'not a roll' unless t['kind'] == 'roll'
    r = t['roll']
    initial = Array.new(r['dice_count']) { rng.rand(1..die_size) }
    final, rerolled = ActionFlow.apply_rerolls(initial, r['tn'], r['positive_reroll'].to_i, r['negative_reroll'].to_i, rng)
    decide(task_id, { 'dice' => initial, 'rerolled' => rerolled, 'final' => final })
  end

  def cancel! = @status = 'cancelled'
  def done! = @status = 'done'

  # For the DM's pre-filled Attack builder: the choices in builder step order
  # and each Roll's result.
  def prefill
    order = Array(@blob && @blob[:steps]).map { |s| s[:key].to_s }
    {
      flow_id: @id, kind: @kind, ability: @ability, attacker_id: @actor_id, actor_id: @actor_id,
      choices: order.filter_map { |k| [k, @choices[k]] if @choices.key?(k) },
      rolls: @rolls.transform_values { |r| r.slice('successes', 'crits', 'final', 'tn', 'starting_value') }
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

  def self.dois(final, tn, starting_value)
    size = die_size
    starting_value.to_i + final.sum do |v|
      if v == size then 2
      elsif v == 1 then -1
      elsif v >= tn then 1
      else 0
      end
    end
  end

  # Cross-side propagation (check_resolution_design.md; public/js/propagation.js):
  # the initiating Roll takes every opposing Roll's entries inverted, the
  # defending Roll every supporting Roll's, and the others only the lead Roll
  # of the other side. Ascendancy entries and a Roll's no_propagate Types never
  # cross. Returns { roll_id => propagated bonus_penalty_list }.
  def self.propagate(supporting, opposing)
    extend = lambda do |roll, sources|
      list = Array(roll['bonus_penalty_list']).map(&:dup)
      sources.each do |src|
        next if src.nil? || src.equal?(roll)
        skip = Array(src['no_propagate'])
        Array(src['bonus_penalty_list']).each do |type, value, from|
          next if skip.include?(type) || type == 'Ascendancy'
          list << (from.nil? ? [type, -value] : [type, -value, from])
        end
      end
      list
    end
    out = {}
    supporting.each_with_index { |r, i| out[r['id']] = extend.call(r, i.zero? ? opposing : [opposing.first]) }
    opposing.each_with_index { |r, j| out[r['id']] = extend.call(r, j.zero? ? supporting : [supporting.first]) }
    out
  end

  private

  def die_size = ActionFlow.die_size

  def new_task(stage, step, owner_id, extra = {})
    t = { 'id' => SecureRandom.hex(4), 'stage' => stage, 'step' => step,
          'kind' => (stage == 'roll' ? 'roll' : (stage == 'declare' ? 'declare' : 'choice')),
          'owner_id' => owner_id, 'owner_name' => name_of(owner_id),
          'status' => 'waiting', 'value' => nil, 'summary' => nil, 'by' => nil }.merge(extra)
    @tasks << t
    t
  end

  def step_def(key) = Array(@blob && @blob[:steps]).find { |s| s[:key].to_s == key }

  # Options of a builder step under the current choices (static list or the
  # choice-dependent options_map entry), as the builder would show them.
  def raw_options(key)
    step = step_def(key) or return []
    return Array(step[:options]) if step[:options]
    return [] unless step[:options_by]
    map_key = Array(step[:options_by]).map { |s| choice_key(s.to_s) }.join('|')
    Array((step[:options_map] || {})[map_key] || (step[:options_map] || {})[map_key.to_sym])
  end

  # The builder keys choice-dependent maps by each prior option's `key`
  # (falling back to its value).
  def choice_key(step_key)
    v = @choices[step_key]
    return '' if v.nil?
    opt = raw_options(step_key).find { |o| o[:value].to_s == v.to_s }
    (opt && !opt[:key].nil? ? opt[:key] : v).to_s
  end

  def clean(label) = CGI.unescapeHTML(label.to_s.gsub(/<[^>]*>/, '')).strip

  def step_options(key)
    seen = {}
    groups = []
    opts = raw_options(key).filter_map do |o|
      next if o[:kind] == 'info' || o[:header_only]
      v = o[:value].to_s
      next if seen[v] # the builder's lead "max dice" button repeats a count
      seen[v] = true
      head, dice = v.split('|', 2)
      dice_n = dice.to_s.match?(/\A\d+\z/) ? dice.to_i : nil
      summary = clean(o[:summary] || o[:label])
      group = (o[:group] || head).to_s
      groups << group unless groups.include?(group)
      { value: v, label: clean(o[:label]), summary: summary,
        group: group, group_label: summary.split(' — ').first.to_s,
        dice: dice_n, disabled: !!o[:disabled] }
    end
    # Builder order of the groups; dice counts ascending within a group.
    opts.sort_by { |o| [groups.index(o[:group]), o[:dice] || 0] }
  end

  def luck_step_def(step_key) = step_def(step_key)

  def luck_options(step_key)
    step = luck_step_def(step_key) or return []
    src  = step.dig(:luck, :source) || {}
    sid  = src[:sid].to_s
    out  = [{ value: "#{sid}|none", label: 'No luck', summary: "#{src[:label]}: no luck", group: 'none',
              group_label: 'No luck', dice: nil, disabled: false }]
    Array(step.dig(:luck, :targets)).each do |tgt|
      rid = tgt[:roll_id].to_s
      roll = current_rolls[rid]
      next if roll.nil? || roll['excluded']
      cap = [src[:amount].to_i, roll['dice_count'].to_i].min
      next unless cap.positive?
      who = roll_label(roll, tgt[:label])
      (1..cap).each do |n|
        out << { value: "#{sid}|pos|#{n}|#{rid}", label: "+#{n}", summary: "#{src[:label]}: +#{n} reroll on #{who}",
                 group: "pos:#{rid}", group_label: "Help #{who} (reroll low dice)", dice: n, disabled: false }
      end
      next unless src[:penalty]
      (1..cap).each do |n|
        out << { value: "#{sid}|neg|#{n}|#{rid}", label: "−#{n}", summary: "#{src[:label]}: −#{n} reroll on #{who}",
                 group: "neg:#{rid}", group_label: "Hinder #{who} (reroll high dice)", dice: n, disabled: false }
      end
    end
    out
  end

  def roll_label(roll, fallback)
    name = roll['creature_name'].to_s
    rn = roll['roll_name'].to_s
    name.empty? || name == '—' ? fallback.to_s : "#{name}'s #{rn.downcase}"
  end

  # The attack's request in words; other kinds pass their own summary.
  def declare_summary
    d = @declare.to_h
    opt = raw_options('action').find { |o| o[:value].to_s == d['action'] }
    "#{opt ? clean(opt[:summary] || opt[:label]) : d['action']} at #{name_of(d['target'].to_i)}"
  end

  # A Spell option that rolls no check (a buff, a Reservoir pour): the builder
  # skips Luck and the dice table for it (ActionBuilder `noRoll`).
  def no_roll?
    opt = raw_options('spell').find { |o| o[:value].to_s == @choices['spell'].to_s }
    !!(opt && opt[:cast] && !opt[:cast][:roll])
  end

  # An area Spell: the DM places it on the map, which decides who saves.
  def area? = @choices['target'].to_s == 'place'

  def to_resolve! = @stage = 'resolve'
  public :area?, :no_roll?

  # --- Stage transitions -------------------------------------------------------------

  def advance!
    case @stage
    when 'declare' then start_respond!
    when 'respond' then start_luck!
    when 'luck'    then start_roll!
    when 'roll'    then @stage = 'resolve'
    end
  end

  def start_respond!
    @declare.each { |k, v| @choices[k] = v }
    @stage = 'respond'
    return to_resolve! if @blob.nil? || area?
    defense = step_options('defense')
    auto = raw_options('defense').select { |o| o[:kind] != 'info' && !o[:header_only] }
    if auto.length == 1 && auto.first[:auto]
      @choices['defense'] = auto.first[:value].to_s # a Saving Throw: full Dice Cap, nothing to ask
    elsif !defense.empty? && target_id
      new_task('respond', 'defense', target_id)
    end
    shield = raw_options('ally_defense').find { |o| o[:value].to_s.start_with?('shield:') }
    if shield
      caster = shield[:value].to_s.split('|').first.split(':').last.to_i
      new_task('respond', 'ally_defense', caster)
    end
    start_luck! if stage_tasks('respond').empty?
  end

  def start_luck!
    stage_tasks('respond').each { |t| @choices[t['step']] = t['value'] }
    @stage = 'luck'
    return to_resolve! if no_roll?
    Array(@blob[:steps]).each do |s|
      next unless s[:dynamic].to_s == 'luck'
      next if luck_options(s[:key].to_s).length <= 1
      src = s.dig(:luck, :source) || {}
      new_task('luck', s[:key].to_s, src[:id])
    end
    start_roll! if stage_tasks('luck').empty?
  end

  def start_roll!
    stage_tasks('luck').each { |t| @choices[t['step']] = t['value'] }
    @stage = 'roll'
    rolls = current_rolls
    luck = Hash.new { |h, k| h[k] = { pos: 0, neg: 0 } }
    @choices.each do |k, v|
      next unless k.start_with?('luck:')
      _sid, sign, n, rid = v.to_s.split('|')
      next if sign.nil? || sign == 'none' || rid.nil?
      key = sign == 'pos' ? :pos : :neg
      luck[rid][key] = [luck[rid][key], n.to_i].max
    end
    included = rolls.values.reject { |r| r['excluded'] || r['dice_count'].to_i <= 0 }
    sup = included.select { |r| r['side'] == 'supporting' }
    opp = included.select { |r| r['side'] == 'opposing' }
    lists = ActionFlow.propagate(sup, opp)
    shield_caster = @choices['ally_defense'].to_s.start_with?('shield:') ? @choices['ally_defense'].split('|').first.split(':').last.to_i : nil
    included.each do |r|
      tn = DiceResolution.compute_target_number(lists[r['id']])
      owner = case r['id']
              when 'attacker', 'caster', 'performance' then @actor_id
              when 'defender', 'target' then target_id
              when 'shield' then shield_caster
              end
      roll = { 'roll_id' => r['id'], 'name' => r['roll_name'].to_s, 'creature_name' => r['creature_name'].to_s,
               'dice_count' => r['dice_count'].to_i, 'tn' => tn[:tn], 'starting_value' => tn[:starting_value],
               'positive_reroll' => luck[r['id']][:pos], 'negative_reroll' => luck[r['id']][:neg],
               'speed' => r['speed'].to_i }
      new_task('roll', "roll:#{r['id']}", owner, 'roll' => roll)
    end
    @stage = 'resolve' if stage_tasks('roll').empty?
  end

  # The builder's seed Rolls with every chosen option's patch applied, in step
  # order (a Ruby port of ActionBuilder._applyPatch). Keyed by roll id.
  def current_rolls
    rolls = Array(@blob[:rolls]).to_h { |r| [r[:id].to_s, r.transform_keys(&:to_s)] }
    Array(@blob[:steps]).each do |s|
      key = s[:key].to_s
      next unless @choices.key?(key) && s[:dynamic].nil?
      opt = raw_options(key).find { |o| o[:value].to_s == @choices[key].to_s }
      apply_patch!(rolls, opt && opt[:patch])
    end
    rolls
  end

  def apply_patch!(rolls, patch)
    return unless patch
    each = ->(name) { Array(patch[name]).each { |p| (r = rolls[p[:id].to_s]) && yield_patch(name, r, p) } }
    %i[set_dice scale_dice restore_dice set_speed set_bpl set_no_propagate set_name set_excluded].each { |n| each.call(n) }
  end

  def yield_patch(name, r, p)
    case name
    when :set_dice then r['dice_count'] = p[:count].to_i; r.delete('_base_dice')
    when :scale_dice
      r['_base_dice'] ||= r['dice_count'].to_i
      base = r['_base_dice']
      scaled = (base * (p[:num] || 1).to_i) / (p[:den] || 1).to_i
      r['dice_count'] = [base, [(p[:min] || 1).to_i, scaled].max].min
    when :restore_dice
      if r['_base_dice'] then r['dice_count'] = r['_base_dice']; r.delete('_base_dice') end
    when :set_speed then r['speed'] = p[:speed].to_i
    when :set_bpl then r['bonus_penalty_list'] = Array(p[:bonus_penalty_list]).map { |e| Array(e) }
    when :set_no_propagate then r['no_propagate'] = Array(p[:types])
    when :set_name
      r['creature_name'] = p[:creature_name] if p.key?(:creature_name)
      r['roll_name'] = p[:roll_name] if p.key?(:roll_name)
    when :set_excluded then r['excluded'] = !!p[:excluded]
    end
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
    successes = ActionFlow.dois(final, r['tn'], r['starting_value'])
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
  def synchronize(&block) = @mutex.synchronize(&block)
  def clear! = @mutex.synchronize { @flows.clear }
end
