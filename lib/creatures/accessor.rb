require_relative 'config'
require_relative 'advancement'
require_relative 'races'
require_relative 'deities'
require_relative 'formula'
require_relative 'dataset'
require_relative '../proficiencies/ranks'

module Creatures
  # Read-only accessor over a single Creature Record. Reads fresh
  # from the underlying record each call (no snapshotting).
  class Accessor
    SPELLCASTING_ABILITIES = %w[
      bardic_spellcasting arcane_spellcasting druidic_spellcasting
      ranger_spellcasting domain
    ].freeze

    def initialize(record)
      @record = record
    end

    # ---- identity ----
    def id        ; @record[:id]     ; end
    def name      ; @record[:name]   ; end
    def player    ; @record[:player] ; end
    def group     ; @record[:group]  ; end
    def tags      ; @record[:tags]   ; end
    def race      ; @record[:race]   ; end
    def record    ; @record          ; end

    # Per-Creature token image (a web path), stored under `metadata`
    # (the design's portrait-path slot). Nil when unset — the Atlas
    # token then falls back to a `?` marker. See atlas_stub.md.
    def creature_token
      (@record[:metadata] || {})['creature_token']
    end

    # ---- attributes ----
    def base_attribute_value(attr)
      @record[:attributes][attr.to_sym]
    end

    def attribute_value(attr)
      effective_attributes[attr.to_sym]
    end

    def effective_attributes
      @effective ||= compute_effective_attributes
    end

    # ---- tier ----
    def tier
      return @record[:tier] if @record[:tier]
      compute_tier
    end

    def total_level
      @record[:classes].values.sum { |e| e[:level] }
    end

    def class_summary
      @record[:classes].map { |k, e| [k, e[:level]] }
    end

    def level_for_class(class_key)
      entry = @record[:classes][class_key.to_s]
      entry ? entry[:level] : 0
    end

    def tier_attribute_advancement
      @record[:tier_attribute_advancement]
    end

    # ---- speed / HP / Mana ----
    def speed
      race = Creatures::Races.look_up(@record[:race])
      base = race && race[:speed]
      base ||= Creatures::Config.data['Default Base Speed'] || 30

      bonus = aggregated_modifiers(target: 'speed').sum { |m| m[:amount] }
      [base + bonus, 0].max
    end

    def max_hit_points
      formulas = Creatures::Advancement.data['HP Formula'] || []
      t = tier
      raise "Tier #{t} beyond HP Formula range" if t >= formulas.length
      base = Creatures::Formula.eval(formulas[t], hp_formula_vars)
      base + aggregated_modifiers(target: 'hp_bonus').sum { |m| m[:amount] }
    end

    def max_mana
      formulas = Creatures::Advancement.data['Mana Base Formula'] || []
      t = tier
      raise "Tier #{t} beyond Mana Base Formula range" if t >= formulas.length
      base = Creatures::Formula.eval(formulas[t], mana_formula_vars)
      class_contrib = @record[:classes].sum do |key, entry|
        cls = Creatures::Advancement.look_up_class(key) || {}
        Integer(cls['mana_per_level'] || 0) * entry[:level]
      end
      base + class_contrib + aggregated_modifiers(target: 'mana_bonus').sum { |m| m[:amount] }
    end

    # ---- ranks ----
    def ranks_for(key)
      key = key.to_s
      if key == 'martial'
        martial_ranks
      elsif key.end_with?('_save')
        save_ranks(key.sub(/_save\z/, '').to_sym)
      else
        skill_ranks(key)
      end
    end

    # ---- granted abilities ----
    # Returns [{name:, source:}] where source is 'race' or 'class:<key>'.
    def granted_abilities(source: nil)
      list = []
      seen = {}
      push = lambda do |name, src|
        next if seen[name]
        list << { name: name, source: src }
        seen[name] = true
      end

      # Race chain abilities filtered by min_level <= Tier.
      race = Creatures::Races.look_up(@record[:race])
      (race && race[:abilities] || []).each do |ab|
        push.call(ab[:name], 'race') if ab[:min_level] <= tier
      end

      # Class progression + granted_spells + choices (deity/domain + spellcasting).
      @record[:classes].each do |key, entry|
        cls = Creatures::Advancement.look_up_class(key)
        next unless cls

        progression = cls['ability_progression'] || {}
        progression.keys.sort_by(&:to_i).each do |level_key|
          next if Integer(level_key) > entry[:level]
          Array(progression[level_key]).each { |name| push.call(name, "class:#{key}") }
        end

        Array(cls['granted_spells']).each { |name| push.call(name, "class:#{key}") }

        # Deity / domain spells (Cleric pattern).
        if entry[:choices]['deity'] && entry[:choices]['domain']
          Creatures::Deities.domain_spells(
            entry[:choices]['deity'], entry[:choices]['domain']
          ).each { |name| push.call(name, "class:#{key}") }
        end

        # choices.spellcasting — only when the Class progression
        # actually granted a Spellcasting-type ability up to the
        # Creature's Class Level.
        casting_picks = Array(entry[:choices]['spellcasting'])
        next if casting_picks.empty?
        granted_so_far = progression.select { |lvl, _| Integer(lvl) <= entry[:level] }
                                   .values.flatten
        if granted_so_far.any? { |a| SPELLCASTING_ABILITIES.include?(a) }
          casting_picks.each { |name| push.call(name, "class:#{key}") }
        end
      end

      filter_by_source(list, source)
    end

    def filter_by_source(list, source)
      return list unless source
      case source.to_s
      when 'race'  then list.select { |g| g[:source] == 'race' }
      when 'class' then list.select { |g| g[:source].start_with?('class:') }
      else              list.select { |g| g[:source] == source }
      end
    end

    def has_ability(name)
      granted_abilities.any? { |g| g[:name] == name }
    end

    def level_for_ability(name)
      g = granted_abilities.find { |x| x[:name] == name }
      return 0 unless g
      if g[:source] == 'race'
        tier
      elsif g[:source].start_with?('class:')
        class_key = g[:source].sub(/\Aclass:/, '')
        level_for_class(class_key)
      else
        0
      end
    end

    # ---- aggregated modifiers ----
    # Stub until the Abilities domain lands. Returns an empty list
    # for any target so consumers (Speed, HP/Mana bonuses, Combat)
    # can call uniformly without nil-checking.
    def aggregated_modifiers(target: nil)
      []
    end

    private

    def compute_tier
      lists = Creatures::Advancement.breakpoints
      matching = @record[:tags].select { |t| lists.key?(t) }
      total = total_level
      if matching.any?
        matching.map { |t| tier_for_breakpoints(lists[t], total) }.max
      else
        # No tag matched — cautious fallback: minimum Tier across every list.
        lists.values.map { |bp| tier_for_breakpoints(bp, total) }.min || 0
      end
    end

    def tier_for_breakpoints(breakpoints, total_level)
      best = 0
      breakpoints.each_with_index do |bp, i|
        best = i if bp <= total_level
      end
      best
    end

    def compute_effective_attributes
      attrs = Creatures::Config.attribute_keys
      base = @record[:attributes]

      race = Creatures::Races.look_up(@record[:race])
      racial = race ? race[:attribute_adjustments] : Hash.new(0)

      per_tier_table = Creatures::Config.tier_minimum_inherent_bonus
      per_tier = per_tier_table[tier] || 0

      counts = Creatures::Config.tier_inherent_chosen_bonus_count
      amount = Creatures::Config.per_tier_inherent_chosen_bonus_amount

      # Chunk tier_attribute_advancement into per-tier slices,
      # consuming `counts[t]` entries from the head for each Tier
      # from 2 up to the Creature's current Tier. Anything past the
      # current Tier's reach doesn't apply.
      chosen = Hash.new(0)
      offset = 0
      (2..tier).each do |t|
        take = counts[t] || 0
        slice = @record[:tier_attribute_advancement][offset, take] || []
        slice.each { |attr| chosen[attr] += amount }
        offset += take
      end

      attrs.each_with_object({}) do |a, h|
        h[a] = base[a] + (racial[a] || 0) + per_tier + chosen[a]
      end
    end

    def skill_ranks(skill_key)
      @record[:classes].sum do |class_key, entry|
        Proficiencies::Ranks.ranks_for_skill(class_key, entry[:level], skill_key, trained: trained?(class_key, skill_key))
      end
    end

    def save_ranks(attr_key)
      @record[:classes].sum do |class_key, entry|
        cls = Creatures::Advancement.look_up_class(class_key) || {}
        saves = cls['saves'] || {}
        rate = (saves['aligned'] || []).include?(attr_key.to_s) ? :aligned : :opposed
        Proficiencies::Ranks.apply_rate(entry[:level], rate)
      end
    end

    def martial_ranks
      @record[:classes].sum do |class_key, entry|
        cls = Creatures::Advancement.look_up_class(class_key) || {}
        rate = (cls['martial_advancement'] || 'unaligned').to_sym
        Proficiencies::Ranks.apply_rate(entry[:level], rate)
      end
    end

    def trained?(class_key, skill_key)
      entry = @record[:classes][class_key.to_s]
      return false unless entry
      entry[:skills].include?(skill_key.to_s)
    end

    def hp_formula_vars
      ea = effective_attributes
      { str: ea[:str], dex: ea[:dex], con: ea[:con],
        int: ea[:int], wis: ea[:wis], cha: ea[:cha], tier: tier, level: total_level }
    end
    alias mana_formula_vars hp_formula_vars
  end
end
