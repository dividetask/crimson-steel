module Abilities
  # Turns a raw Catalog Ability into a resolved Variant and answers the
  # per-Ability resolution questions (range, activation, target). A
  # resolved Variant is a fresh Hash (the Catalog is never mutated) with:
  #   - inheritance applied (parent resolved first, child shallow-overrides)
  #   - the Variant at axis_index selected (parallel lists + overrides)
  #   - Effect Hash resolved (axis picks + cross-reference formulas)
  #   - defaults applied; universal skills/forms appended (Spells)
  #   - {name} / {aspect} substitution performed on display strings
  #   - a constructed `name`
  #
  # Formula evaluation during resolution is best-effort: an Effect Hash
  # entry whose Formula references a name not yet bound (e.g. `level`
  # supplied later by Creatures, or a damage-only variable) is left as
  # its raw string rather than raising, so a lookup never crashes on data
  # it cannot fully evaluate without runtime context.
  class Resolver
    def initialize(catalog)
      @catalog = catalog
      @config = catalog.config
    end

    # Returns the resolved Variant Hash, or nil if the name is unknown.
    # Raises IndexError for an out-of-range axis_index.
    def resolve(name, axis_index: 0, bindings: {}, _stack: [])
      raw = @catalog.ability(name)
      return nil unless raw

      key = name.to_s
      if _stack.include?(key)
        raise ArgumentError, "circular inheritance through #{key}"
      end

      base =
        if raw['inherits_from']
          parent = resolve(raw['inherits_from'], axis_index: 0, bindings: bindings, _stack: _stack + [key])
          child = deep_dup(raw)
          child.delete('inherits_from')
          parent.merge(child)
        else
          deep_dup(raw)
        end

      resolve_variant(key, base, axis_index, bindings)
    end

    # ---- Per-Ability resolution ----------------------------------------

    def resolve_range(ability, rank: 0, reach: nil)
      r = ability['range']
      return nil if r.nil?
      return r if r.is_a?(Integer)
      formula = @config.range_formulas[r]
      raise ArgumentError, "unknown range #{r.inspect}" unless formula
      reach ||= @config.default_reach_feet
      Formula.evaluate(formula, 'rank' => rank, 'reach' => reach)
    end

    def resolve_activation(ability)
      at = ability['activation_time'] || (ability['trigger'] ? 'free' : 'main')
      if @config.action_aliases.key?(at)
        { kind: :action, alias: at, value: @config.action_aliases[at] }
      elsif @config.real_time_aliases.key?(at)
        { kind: :real_time, alias: at, minutes: @config.real_time_aliases[at] }
      elsif (m = at.match(/\A(\d+)\s+turns?\z/))
        { kind: :turns, turns: m[1].to_i }
      elsif (m = at.match(/\A(\d+)\s+minutes?\z/))
        { kind: :real_time, minutes: m[1].to_i }
      else
        raise ArgumentError, "unknown activation_time #{at.inspect}"
      end
    end

    def resolve_target(ability, rank: 0, bindings: {})
      t = ability['target']
      return nil if t.nil?
      return 'self' if t == 'self'
      return 'object' if t == 'object'
      return t if t.is_a?(Integer)
      s = t.to_s
      return s.to_i if s.match?(/\A-?\d+\z/)
      begin
        ctx = { 'rank' => rank }
        bindings.each { |k, v| ctx[k.to_s] = v }
        value = Formula.evaluate(s, ctx)
        value.is_a?(Float) ? value.floor : value
      rescue Formula::UnresolvedName, ArgumentError
        t
      end
    end

    private

    def resolve_variant(key, raw, axis_index, bindings)
      a = raw
      tier = a['tier']
      aspects = a['aspects']
      len = if tier.is_a?(Array) then tier.length
            elsif aspects.is_a?(Array) then aspects.length
            else 1
            end
      if axis_index.negative? || axis_index >= len
        raise IndexError, "axis_index #{axis_index} out of range (#{key} has #{len} variant(s))"
      end

      aspect_label = aspects.is_a?(Array) ? aspects[axis_index] : nil
      tier_value = tier.is_a?(Array) ? tier[axis_index] : tier

      Catalog::PARALLEL_FIELDS.each do |field|
        a[field] = a[field][axis_index] if a[field].is_a?(Array)
      end

      overrides = a['variant_overrides']
      if overrides.is_a?(Array) && overrides[axis_index].is_a?(Hash)
        overrides[axis_index].each do |k, v|
          v.nil? ? a.delete(k) : a[k] = v
        end
      end

      prefix = a.delete('prefix')
      suffix = a.delete('suffix')
      name_part = a['name']
      a.delete('variant_overrides')
      a.delete('aspects')
      a['tier'] = tier_value unless tier_value.nil?

      context = build_context(tier_value, bindings)
      a['effect_hash'] = resolve_effect_hash(a['effect_hash'], axis_index, len, context)

      apply_defaults!(a)
      append_universal!(a)

      a['name'] = construct_name(name_part, prefix, suffix, key)

      sub = substitution_context(a['effect_hash'], a['name'], aspect_label)
      a['description'] = substitute(a['description'], sub) if a['description']
      resolve_channel!(a, axis_index, len, bindings, a['name'], aspect_label)

      a
    end

    def build_context(tier_value, bindings)
      ctx = {}
      bindings.each { |k, v| ctx[k.to_s] = v }
      ctx['rank'] ||= 0
      tv = tier_value.nil? ? ctx['tier'] : tier_value
      tv = 0.5 if tv == 0
      ctx['tier'] = tv unless tv.nil?
      ctx
    end

    def resolve_effect_hash(hash, axis_index, len, context)
      return hash unless hash.is_a?(Hash)
      ctx = context.dup
      resolved = {}
      hash.each do |k, v|
        value =
          if v.is_a?(Array)
            len > 1 ? v[axis_index] : v
          elsif v.is_a?(String)
            begin
              Formula.evaluate(v, ctx)
            rescue Formula::UnresolvedName
              v
            end
          else
            v
          end
        resolved[k] = value
        ctx[k] = value
      end
      resolved
    end

    def apply_defaults!(a)
      spell = (a['type'] == 'spell')
      a['skills'] ||= ['arcana'] if spell
      a['save'] ||= []
      a['items'] ||= [] if spell
      if a['requires_willing'].nil?
        a['requires_willing'] = (a['target'] == 'self')
      end
      a['activation_time'] ||= (a['trigger'] ? 'free' : 'main')
    end

    def append_universal!(a)
      return unless a['type'] == 'spell'
      if a['skills']
        extra = @config.universal_casting_skills.reject { |s| a['skills'].include?(s) }
        a['skills'] = a['skills'] + extra
      end
      unless a['item_only']
        items = a['items'] || []
        extra = @config.universal_item_forms.reject { |i| items.include?(i) }
        a['items'] = items + extra
      end
    end

    def construct_name(name_part, prefix, suffix, key)
      return name_part if name_part.is_a?(String) && !name_part.strip.empty?
      [prefix, key, suffix].reject { |p| p.nil? || p.to_s.strip.empty? }.join(' ')
    end

    def substitution_context(effect_hash, name, aspect_label)
      ctx = {}
      (effect_hash || {}).each { |k, v| ctx[k.to_s] = v }
      ctx['name'] = name
      ctx['aspect'] = aspect_label if aspect_label
      ctx
    end

    def substitute(str, ctx)
      str.gsub(/\{(\w+)\}/) { |m| ctx.key?($1) ? ctx[$1].to_s : m }
    end

    def resolve_channel!(a, axis_index, len, bindings, name, aspect_label)
      ch = a['channel']
      return unless ch.is_a?(Hash)
      ch_context = build_context(a['tier'], bindings)
      ch['effect_hash'] = resolve_effect_hash(ch['effect_hash'], axis_index, len, ch_context) if ch['effect_hash']
      ch_sub = substitution_context(ch['effect_hash'], name, aspect_label)
      ch['description'] = substitute(ch['description'], ch_sub) if ch['description']
    end

    def deep_dup(obj)
      Marshal.load(Marshal.dump(obj))
    end
  end
end
