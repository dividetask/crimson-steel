require 'equipment'

# Recorded-call stubs for the sibling domains, per equipment_tests.md
# ("Conditions, Combat, and Abilities are mocked as recorded-call
# stubs"). Each stub records the calls Equipment makes so specs can
# assert on the Conditions / Combat / Abilities side-effects.

class FakeCreatureAccessor
  def initialize(inventories = {})
    @inv = {}
    inventories.each { |k, v| @inv[k.to_s] = v.map { |s| Equipment::Stack.normalize(s) } }
  end

  def get_inventory(id)         ; @inv[id.to_s] || []        ; end
  def set_inventory(id, stacks) ; @inv[id.to_s] = stacks      ; end
  def source_file_for(_id)      ; 'creatures_data.yaml'       ; end
  def exists?(id)               ; @inv.key?(id.to_s)          ; end
  def raw(id)                   ; @inv[id.to_s]               ; end
end

class RecordingConditions
  attr_reader :applied, :removed_prefixes, :heals, :toxicities, :temp_hps
  attr_accessor :magic_toxicity

  def initialize(magic_toxicity: 0)
    @applied = []
    @removed_prefixes = []
    @heals = []
    @toxicities = []
    @temp_hps = []
    @magic_toxicity = magic_toxicity
  end

  def apply_effect(effect)            ; @applied << effect ; nil          ; end
  def remove_effects_by_prefix(pfx)   ; @removed_prefixes << pfx ; []     ; end
  def apply_heal(severity_map)        ; @heals << severity_map ; severity_map ; end
  def apply_magic_toxicity(**kw)      ; @toxicities << kw ; { accepted: true } ; end
  def apply_temporary_hit_points(**kw); @temp_hps << kw ; { accepted: true }   ; end
end

class RecordingCombat
  attr_reader :damages
  def initialize ; @damages = [] ; end
  def apply_damage(**kw) ; @damages << kw ; nil ; end
end

# Deterministic RNG: yields queued floats for `rand` (no-arg, [0,1)),
# and derives integer / range draws from the same queue so dice and
# weighted picks are reproducible. Falls back to a seeded Random once
# the queue drains.
class SequenceRng
  def initialize(floats = [])
    @floats = floats.dup
    @fallback = Random.new(20260528)
  end

  def rand(arg = nil)
    f = @floats.empty? ? @fallback.rand : @floats.shift
    if arg.nil?
      f
    elsif arg.is_a?(Range)
      span = arg.last - arg.first + 1
      arg.first + (f * span).floor.clamp(0, span - 1)
    else
      (f * arg).floor
    end
  end
end

class RecordingAbilities
  def initialize(spells: {}, item_only: [])
    @spells = spells
    @item_only = item_only
  end

  def item_only?(name) ; @item_only.include?(name.to_s) ; end

  # Returns { effects: [...], polarity: :positive | :forced } for a
  # spell resolved at a tier.
  def resolve_spell(name, tier:)
    entry = @spells[name.to_s] || {}
    entry = entry.call(tier) if entry.is_a?(Proc)
    { effects: (entry[:effects] || []), polarity: (entry[:polarity] || :positive) }
  end
end
