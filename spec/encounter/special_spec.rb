require 'spec_helper'
require 'encounter'
require 'abilities'
require 'conditions'
require 'tmpdir'

RSpec.describe Encounter::Special do
  describe '.usable?' do
    def action(alias_name) = { kind: :action, alias: alias_name }

    it 'admits a Talent with an explicit non-Reaction activation_time' do
      raw = { 'type' => 'talent', 'activation_time' => 'main' }
      expect(described_class.usable?(raw, action('main'))).to be true
      raw_free = { 'type' => 'talent', 'activation_time' => 'free' }
      expect(described_class.usable?(raw_free, action('free'))).to be true
    end

    it 'rejects Reactions' do
      raw = { 'type' => 'talent', 'activation_time' => 'reaction' }
      expect(described_class.usable?(raw, action('reaction'))).to be false
    end

    it 'rejects Spells' do
      raw = { 'type' => 'spell', 'activation_time' => 'main' }
      expect(described_class.usable?(raw, action('main'))).to be false
    end

    it 'rejects Talents with no explicit activation_time (trigger riders / passives)' do
      trigger = { 'type' => 'talent', 'trigger' => { 'on' => 'on_hit' } }
      expect(described_class.usable?(trigger, action('free'))).to be false
      passive = { 'type' => 'talent', 'effects' => ['trapfinding'] }
      expect(described_class.usable?(passive, action('main'))).to be false
    end

    it 'rejects a real-time (ritual) activation' do
      raw = { 'type' => 'talent', 'activation_time' => '10 minutes' }
      expect(described_class.usable?(raw, { kind: :real_time, minutes: 10 })).to be false
    end
  end

  describe '.action_cost' do
    it 'charges the Action Minimum for the action category' do
      expect(described_class.action_cost('free')).to eq(Encounter::Config.free_action_minimum)
      expect(described_class.action_cost('bonus')).to eq(Encounter::Config.bonus_action_minimum)
      expect(described_class.action_cost('main')).to eq(Encounter::Config.main_action_minimum)
    end
  end

  describe '.named_effects' do
    it 'keeps Effect Names and drops damage / none expressions' do
      expect(described_class.named_effects(['rage', '0', '2 damage'])).to eq(['rage'])
    end
  end
end

RSpec.describe 'Encounter::State special actions' do
  let(:tmpdir)    { Dir.mktmpdir('enc-special') }
  let(:data_path) { File.join(tmpdir, 'encounter_data.json') }
  after { FileUtils.remove_entry(tmpdir) if File.exist?(tmpdir) }

  # A Bard-like Creature double. `abilities` is the Granted Abilities list
  # ([{name:, source:}]); the rest is what Combat Pool / Mana need.
  def creature(abilities)
    obj = Object.new
    obj.define_singleton_method(:granted_abilities) { |source: nil| abilities }
    obj.define_singleton_method(:tier) { 1 }
    obj.define_singleton_method(:attribute_value) { |_a| 14 }
    obj.define_singleton_method(:ranks_for) { |_k| 6 }
    obj.define_singleton_method(:max_hit_points) { 30 }
    obj.define_singleton_method(:max_mana) { 10 }
    obj.define_singleton_method(:tags) { [] }
    obj.define_singleton_method(:name) { 'Lyric' }
    obj.define_singleton_method(:record) { { classes: { 'bard' => { level: 5 } } } }
    obj
  end

  def state(cre, cond = Conditions::Instance.new)
    Encounter::State.new({}, data_path: data_path,
                         creature_lookup: ->(_id) { cre },
                         conditions_for: ->(_id) { cond })
  end

  let(:bard_abilities) do
    [{ name: 'bardic_inspiration', source: 'class:bard' },
     { name: 'rage',              source: 'class:bard' },
     { name: 'primal_tenacity',   source: 'class:bard' }, # reaction — excluded
     { name: 'trapfinding',       source: 'class:bard' }, # passive — excluded
     { name: 'sneak_attack',      source: 'class:bard' }] # trigger — excluded
  end

  describe '#special_options' do
    it 'lists only non-Spell, non-Reaction, explicitly-activated Talents' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      names = s.special_options(c[:id]).map { |o| o[:name] }
      expect(names).to contain_exactly('Bardic Inspiration', 'Rage')
    end

    it 'labels a specific Channel Divinity action by its own name and shows mana + dice' do
      # Turn Undead inherits from the "Channel Divinity" category Talent. The
      # option must read "Turn Undead" (not the category) and surface the
      # inherited 1 Mana cost alongside the Combat-Pool dice.
      s = state(creature([{ name: 'Turn Undead', source: 'class:cleric' }]))
      c = s.add_combatant('1')
      tu = s.special_options(c[:id]).find { |o| o[:name] == 'Turn Undead' }
      expect(tu).not_to be_nil
      expect(tu[:label]).to eq('Turn Undead')          # not the "Channel Divinity" category
      expect(tu[:mana_cost]).to eq(1)                  # inherited from Channel Divinity
      expect(tu[:activation]).to eq('main')
      expect(tu[:summary]).to eq("Spend 1 mana and #{Encounter::Config.main_action_minimum} Combat Pool dice.")
    end

    it 'flags Bardic Inspiration as a channeled Performance' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      bi = s.special_options(c[:id]).find { |o| o[:name] == 'Bardic Inspiration' }
      expect(bi[:channeled]).to be true
      expect(bi[:performance]).to be true
      expect(bi[:activation]).to eq('main')
      expect(bi[:mana_cost]).to eq(1)
      expect(bi[:active]).to be false
    end

    it 'summarizes what using the Ability changes' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      opts = s.special_options(c[:id])
      # Rage is a free action (no Combat-Pool clause): "Spend 1 mana, gain the rage condition."
      rage = opts.find { |o| o[:name] == 'Rage' }
      expect(rage[:summary]).to eq('Spend 1 mana, gain the rage condition.')
      # Bardic Inspiration is a channeled Performance — the channel dice are
      # chosen in the roll builder, so the summary quotes no fixed pool number.
      bi = opts.find { |o| o[:name] == 'Bardic Inspiration' }
      expect(bi[:summary]).to eq('Spend 1 mana, begin Bardic Inspiration.')
    end

    it 'disables an Ability the Combatant cannot pay the Mana for' do
      cond = Conditions::Instance.new
      cond.set_mana_spent(amount: 10, mana_max: 10) # no Mana left
      s = state(creature(bard_abilities), cond)
      c = s.add_combatant('1')
      rage = s.special_options(c[:id]).find { |o| o[:name] == 'Rage' }
      expect(rage[:disabled]).to be true
      expect(rage[:disabled_reason]).to eq('not enough Mana')
    end
  end

  describe '#use_special_payload' do
    it 'begins a Bardic Performance, spending the chosen channel dice and filling the Reservoir from the Successes' do
      cond = Conditions::Instance.new
      s = state(creature(bard_abilities), cond)
      c = s.add_combatant('1')
      # The DM channels 6 dice (the Performance check) and rolls 3 Successes.
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Bardic Inspiration', dice: 6, successes: 3)

      expect(out[:ok]).to be true
      expect(out[:performance]).to eq('started')
      expect(out[:reservoir]).to eq(3)
      expect(out[:mana_spent]).to eq(1)
      expect(out[:pool_spent]).to eq(6) # the chosen channel dice, not the Action Minimum
      # Mana debited and the chosen channel dice spent from the Combat Pool.
      expect(cond.state.mana_spent).to eq(1)
      expect(s.combatant(c[:id])[:combat_pool_spent]).to eq(6)
      # A Concentration entry now holds the Performance.
      entry = s.combatant(c[:id])[:concentration].find { |e| e[:spell_name] == 'Bardic Inspiration' }
      expect(entry[:mode]).to eq('reservoir')
      expect(entry[:reservoir]).to eq(3)
    end

    it 'grants the inverse of negative Successes to the DM instead of draining the Reservoir' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      # A failed Performance check: -3 net Successes. The Reservoir stays at 0
      # and the DM (player id null) gains 3 Luck.
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Bardic Inspiration', dice: 6, successes: -3)

      expect(out[:ok]).to be true
      expect(out[:reservoir]).to eq(0)
      expect(out[:dm_luck_gained]).to eq(3)
      expect(out[:dm_luck_points]).to eq(3)
      expect(s.dm_luck_points).to eq(3)
      entry = s.combatant(c[:id])[:concentration].find { |e| e[:spell_name] == 'Bardic Inspiration' }
      expect(entry[:reservoir]).to eq(0)
    end

    it 'keeps DM Luck across a turn cleanup (it does not expire at end of turn/round)' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      s.grant_dm_luck(4)
      s.grant_luck(c[:id], 3) # a Combatant's per-turn Luck, by contrast
      s.apply_per_turn_cleanup(c[:id])
      expect(s.dm_luck_points).to eq(4)          # DM Luck persists
      expect(s.combatant(c[:id])[:luck_points]).to eq(0) # per-turn Luck cleared
    end

    it 'defaults the channel dice to Main Action Minimum when none is supplied' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Bardic Inspiration', successes: 1)
      expect(out[:pool_spent]).to eq(Encounter::Config.main_action_minimum)
    end

    it 'refuses channel dice below Main Action Minimum, spending nothing' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Bardic Inspiration', dice: 2, successes: 1)
      expect(out[:ok]).to be false
      expect(s.combatant(c[:id])[:combat_pool_spent]).to eq(0)
    end

    it 'refuses channel dice beyond Combat Pool Remaining' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      pool = s.combat_pool_remaining(c[:id])
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Bardic Inspiration', dice: pool + 1, successes: 1)
      expect(out[:ok]).to be false
      expect(s.combatant(c[:id])[:combat_pool_spent]).to eq(0)
    end

    it 'continues a running Performance, adding to the Reservoir' do
      cond = Conditions::Instance.new
      s = state(creature(bard_abilities), cond)
      c = s.add_combatant('1')
      s.use_special_payload(combatant_id: c[:id], ability: 'Bardic Inspiration', dice: 4, successes: 2)
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Bardic Inspiration', dice: 5, successes: 4)

      expect(out[:performance]).to eq('continued')
      expect(out[:reservoir]).to eq(6) # 2 + 4
      expect(s.special_options(c[:id]).find { |o| o[:name] == 'Bardic Inspiration' }[:active]).to be true
    end

    it 'discharges the Bardic Inspiration Reservoir to grant Luck to a target' do
      s = state(creature(bard_abilities))
      bard = s.add_combatant('1')
      ally = s.add_combatant('2')
      s.use_special_payload(combatant_id: bard[:id], ability: 'Bardic Inspiration', dice: 6, successes: 4)

      out = s.discharge_luck_reservoir(bard[:id], ally[:id], 3)
      expect(out[:ok]).to be true
      expect(out[:granted]).to eq(3)
      expect(out[:reservoir]).to eq(1) # 4 − 3 left in the Reservoir
      expect(s.combatant(ally[:id])[:luck_points]).to eq(3)
      expect(s.combatant(bard[:id])[:concentration].first[:reservoir]).to eq(1)
    end

    it 'refuses to discharge more Luck than the Reservoir holds, granting nothing' do
      s = state(creature(bard_abilities))
      bard = s.add_combatant('1')
      ally = s.add_combatant('2')
      s.use_special_payload(combatant_id: bard[:id], ability: 'Bardic Inspiration', dice: 4, successes: 2)

      out = s.discharge_luck_reservoir(bard[:id], ally[:id], 5)
      expect(out[:ok]).to be false
      expect(s.combatant(ally[:id])[:luck_points]).to eq(0)
      expect(s.combatant(bard[:id])[:concentration].first[:reservoir]).to eq(2) # unchanged
    end

    it 'gives the rage Condition and its resolved Modifiers to the actor' do
      cond = build_instance # catalog-backed, so the `rage` Effect Name resolves
      s = state(creature(bard_abilities), cond) # bard double is level 5 (record)
      c = s.add_combatant('1')
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Rage')

      expect(out[:ok]).to be true
      expect(out[:applied_effects]).to include('rage')
      expect(out[:mana_spent]).to eq(1)
      # The rage Condition (the `raging` flag) is active...
      expect(cond.active_named_effect_mechanics.any? { |m| m[:data]['flag'] == 'raging' }).to be true
      # ...and its Modifiers resolve to concrete amounts at level 5:
      #   damage_reduction  = 1 + floor(5/3) = 2
      #   damage_resilience = 1 + floor(5/2) = 3
      expect(cond.get_modifiers('damage_reduction')).to eq([['Circumstance', 2]])
      expect(cond.get_modifiers('damage_resilience')).to eq([['Circumstance', 3]])
      expect(cond.active_effect_names).to include('rage')
    end

    it 'Martial Devotion applies its Weapon Training attack bonus as an Active Effect' do
      cond = build_instance
      s = state(creature([{ name: 'Martial Devotion', source: 'class:bard' }]), cond) # level 5
      c = s.add_combatant('1')
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Martial Devotion')

      expect(out[:ok]).to be true
      expect(out[:applied_effects]).to include('martial_devotion')
      expect(out[:mana_spent]).to eq(1) # inherited from the Channel Divinity category
      # Shows in Active Effects (the conditions list) and grants a Competency
      # attack bonus: 1 + floor(level / 4) = 2 at level 5.
      expect(cond.active_effect_names).to include('martial_devotion')
      expect(cond.get_modifiers('attack')).to eq([['Competency', 2]])
    end

    it 'Strength Devotion applies its +2 str/con Active Effect when used' do
      cond = build_instance
      s = state(creature([{ name: 'Strength Devotion', source: 'class:cleric' }]), cond)
      c = s.add_combatant('1')
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Strength Devotion')

      expect(out[:ok]).to be true
      expect(out[:applied_effects]).to include('strength_devotion')
      expect(cond.active_effect_names).to include('strength_devotion')
      # The +2 Morale Modifiers fold into str / con (CreatureModifiers reads them).
      expect(cond.get_modifiers('str')).to eq([['Morale', 2]])
      expect(cond.get_modifiers('con')).to eq([['Morale', 2]])
    end

    it 'rage’s Resilience Modifier raises the Combat damage-bucketing resilience' do
      cond = build_instance
      cre = creature(bard_abilities)
      cre.define_singleton_method(:tier) { 0 } # isolate rage's Modifier from the Tier base
      s = state(cre, cond)
      c = s.add_combatant('1')
      # Before raging: Tier 0 + no armor → 0 resilience, threshold 0 → bucket width 1 (the minimum).
      expect(s.preview_severity(c[:id], 5, 'physical', 0)).to eq(minor: 1, moderate: 1, major: 3)
      s.use_special_payload(combatant_id: c[:id], ability: 'Rage') # +3 Resilience
      # After raging: bucket width = threshold 0 + resilience 3 → 3 Minor, 2 Moderate.
      expect(s.preview_severity(c[:id], 5, 'physical', 0)).to eq(minor: 3, moderate: 2)
    end

    it 'rejects an Ability that is not a usable special action' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Primal Tenacity')
      expect(out[:ok]).to be false
      expect(s.combatant(c[:id])[:combat_pool_spent]).to eq(0)
    end

    it 'rejects an unknown ability without spending anything' do
      s = state(creature(bard_abilities))
      c = s.add_combatant('1')
      out = s.use_special_payload(combatant_id: c[:id], ability: 'Nope')
      expect(out[:ok]).to be false
      expect(s.combatant(c[:id])[:combat_pool_spent]).to eq(0)
    end
  end
end
