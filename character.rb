require_relative 'tools'

class CombatTurn
  # Known condition keys. Each combatant starts at 0 for every condition;
  # a value > 0 means the condition is active on them.
  CONDITION_KEYS = %w[bleed ghoul_paralysis].freeze

  attr_reader :rules, :character, :combat_id, :initiative, :mana, :combat_pool, :minor_damage, :moderate_damage, :major_damage, :saturation, :temporary_hit_points, :conditions

  def initialize(combat_turn, character)
    @rules = Tools.load_json('rules.json')
    @combat_id = combat_turn['id']
    @char_id = combat_turn['char_id'] || combat_turn['id']
    @initiative, @mana, @combat_pool = combat_turn['initiative'], combat_turn['mana'], combat_turn['combat_pool']
    @minor_damage, @moderate_damage, @major_damage = combat_turn['minor_damage'], combat_turn['moderate_damage'], combat_turn['major_damage']
    @saturation = combat_turn['saturation']
    @temporary_hit_points = combat_turn['temporary_hit_points'].to_i
    stored_conditions = combat_turn['conditions'] || {}
    @conditions = CONDITION_KEYS.each_with_object({}) { |k, h| h[k] = stored_conditions[k].to_i }
    @character = CharacterSheet.new(character)
  end

  def condition(name); @conditions[name.to_s].to_i; end
  def active_conditions; @conditions.select { |_, v| v.to_i > 0 }; end

  def new_turn; @combat_pool = @character.combat_pool; end
  def reroll_init
    bonus = @character.respond_to?(:initiative_die_bonus) ? @character.initiative_die_bonus : 0
    @initiative = (1..10).to_a.sample(@character.initiative).map { |i| [i + bonus, 10].min }.sort.reverse.map { |i| i == 10 ? 'X' : i.to_s}.join
  end

  def init_to_a; @initiative.chars.map { |r| r == 'X' ? 10 : r.to_i }.sort.reverse; end

  def to_json
    return {'id' => @combat_id, 'char_id' => @char_id,
      'initiative' => @initiative, 'mana' => @mana, 'combat_pool' => @combat_pool,
      'minor_damage' => @minor_damage, 'moderate_damage' => @moderate_damage, 'major_damage' => @major_damage,
      'saturation' => @saturation, 'temporary_hit_points' => @temporary_hit_points,
      'conditions' => @conditions}
  end

  def hp; return @character.hp_max - @minor_damage - @moderate_damage - @major_damage + @temporary_hit_points.to_i; end

  def display_name(suffix = nil)
    suffix ? "#{@character.name} ##{suffix}" : @character.name
  end
end

class Combat
  attr_reader :combat_turn_list, :current_turn_id, :active_effects

  def initialize
    character_list = Tools.load_json('characters.json')
    combat_data = Tools.load_json('combat.json')
    @current_turn_id = combat_data['current_turn_id'] || 0
    @active_effects = combat_data['active_effects'] || []
    @combat_turn_list = combat_data['participants'].filter_map do |combat_turn|
      char_id = combat_turn['char_id'] || combat_turn['id']
      character = character_list.find { |c| c["id"] == char_id }
      next nil unless character
      CombatTurn.new(combat_turn, character)
    end
    sort_init
  end

  def current_turn_character; @combat_turn_list[@current_turn_id]; end

  def display_name(combat_turn)
    return "Unknown" unless combat_turn&.character
    char_id = combat_turn.character.id
    same = @combat_turn_list.select { |ct| ct.character&.id == char_id }
    return combat_turn.character.name if same.length == 1
    combat_turn.display_name(same.index(combat_turn).to_i + 1)
  end

  def sort_init; @combat_turn_list = @combat_turn_list.sort { |a,b| init_compare(a,b) }; end

  def init_compare(a,b)
    a_list = a.init_to_a
    b_list = b.init_to_a

    a_cur = b_cur = 0
    while ( (a_cur == b_cur) and (a_list.empty? == false) and (b_list.empty? == false) )
      a_cur = a_list.shift
      b_cur = b_list.shift
    end
    return 0 if a_cur == b_cur
    return -1 if a_cur > b_cur or b_cur == nil
    return 1 if b_cur > a_cur or a_cur == nil
  end

  def new_turn; @combat_turn_list.each(&:new_turn); update_data; end

  def reroll_init
    @combat_turn_list.each(&:reroll_init)
    sort_init
    update_data

    # Create new combat log entry
    log = Tools.load_json('combat_log.json')
    log << {
      'date' => Time.now.to_i,
      'participants' => @combat_turn_list.map { |ct| ct.character.id },
      'initiative' => @combat_turn_list.map(&:initiative),
      'log' => []
    }
    Tools.save_json('combat_log.json', log)
  end

  def update_data
    combat_data = Tools.load_json('combat.json')
    combat_data['participants'] = @combat_turn_list.map(&:to_json)
    Tools.save_json('combat.json', combat_data)
  end


  def self.calculate_damage(attacker_id, target_id, weapon_id, action_params)
    action_params['damage'] = 0
    action_params
  end

  def self.advance_turn
    combat_data = Tools.load_json('combat.json')
    num_participants = combat_data['participants'].length
    combat_data['current_turn_id'] = (combat_data['current_turn_id'] + 1) % num_participants
    Tools.save_json('combat.json', combat_data)
  end

  def self.set_current_turn(combat_id)
    combat = Combat.new
    idx = combat.combat_turn_list.find_index { |ct| ct.combat_id == combat_id }
    return unless idx
    combat_data = Tools.load_json('combat.json')
    combat_data['current_turn_id'] = idx
    Tools.save_json('combat.json', combat_data)
  end

  # Worst-first cure cascade. Mutates target's damage counters and returns
  # [healed_major, healed_moderate, healed_minor]. Excess pool (beyond
  # minor_damage) is lost.
  def self.apply_cure_cascade(target, cure_effect)
    major_before = target['major_damage'].to_i
    moderate_before = target['moderate_damage'].to_i
    minor_before = target['minor_damage'].to_i
    pool = cure_effect[:major].to_i
    healed_major = [major_before, pool].min
    pool -= healed_major
    pool += cure_effect[:moderate].to_i
    healed_moderate = [moderate_before, pool].min
    pool -= healed_moderate
    pool += cure_effect[:minor].to_i
    healed_minor = [minor_before, pool].min
    target['major_damage'] = major_before - healed_major
    target['moderate_damage'] = moderate_before - healed_moderate
    target['minor_damage'] = minor_before - healed_minor
    [healed_major, healed_moderate, healed_minor]
  end

  def self.add_log(message)
    log = Tools.load_json('combat_log.json')
    return if log.empty?
    log.last['log'] << message
    Tools.save_json('combat_log.json', log)
  end

  def self.update(id, params, set_keys: [])
    combat_data = Tools.load_json('combat.json')
    participant = combat_data['participants'].find { |p| p['id'] == id }

    return unless participant
    params.each do |k, v|
      if set_keys.include?(k.to_s)
        participant[k.to_s] = v.to_i
      else
        participant[k.to_s] = participant[k.to_s].to_i + v.to_i
      end
    end
    Tools.save_json('combat.json', combat_data)
  end
end

class Compendium
  attr_reader :data

  def initialize; @data = Tools.load_json('compendium.json'); end
  def format_name(ability_name); return ability_name.gsub('_', ' ').split(' ').map(&:capitalize).join(' '); end
  def ability(entry); return @data["abilities"][entry.to_s]; end

  # Returns "none" | "single" | "multi" for a spell variant. Spells without
  # an explicit "target" field default to "single". Unknown spells return
  # nil -- callers (item_effects) decide how to handle that.
  def target_mode(spell_name)
    resolved = resolve_spell_variant(spell_name)
    return nil unless resolved
    _base, spell_data, * = resolved
    mode = spell_data["target"].to_s
    %w[none single multi].include?(mode) ? mode : "single"
  end

  # Given a spell name (which may be a variant like "Cure Lesser Wounds"),
  # return [base_name, spell_data, tier_idx, tier_val] or nil if not found.
  def resolve_spell_variant(spell_name)
    if @data["spells"][spell_name]
      spell_data = @data["spells"][spell_name]
      tier_val = spell_data["tier"].is_a?(Array) ? spell_data["tier"][0] : spell_data["tier"]
      return [spell_name, spell_data, 0, tier_val]
    end
    @data["spells"].each do |base_name, spell_data|
      tiers = spell_data["tier"].is_a?(Array) ? spell_data["tier"] : [spell_data["tier"]]
      tiers.each_with_index do |tier_val, idx|
        variants = []
        variants << "#{spell_data["prefix"][idx]} #{base_name}" if spell_data["prefix"] && spell_data["prefix"][idx]
        variants << "#{base_name} #{spell_data["suffix"][idx]}" if spell_data["suffix"] && spell_data["suffix"][idx]
        return [base_name, spell_data, idx, tier_val] if variants.include?(spell_name)
      end
    end
    nil
  end

  # Look up a base spell by lowercase-underscore key (e.g., "cure" -> "Cure").
  def spell_by_key(key)
    return nil unless key
    normalized = key.to_s.downcase
    @data["spells"].find { |name, _| name.downcase.gsub(' ', '_') == normalized }
  end

  # Returns the resolved effect of a consumable potion or scroll, or nil
  # if the item is not a supported consumable. Potions with spells we don't
  # recognize return nil. Scrolls for unrecognized spells return a :generic
  # entry so they can still be consumed (just no mechanical effect).
  #
  # Output hash shape: {
  #   kind: :potion | :scroll,
  #   type: :cure | :mana | :ward | :generic,
  #   item_tier: Integer,
  #   base_name: String,
  #   variant_name: String,
  #   # cure keys: :minor, :moderate, :major, :saturation, :minimum_saturation
  #   # mana keys: :mana, :saturation, :minimum_saturation
  #   # ward keys: :temp_hp
  # }
  def item_effects(item)
    return nil unless item.is_a?(Hash)
    return nil unless item.dig("properties", "consumable")
    return nil unless %w[potion scroll].include?(item["subtype"])
    kind = item["subtype"].to_sym

    spell_key = item.dig("properties", "spell")
    base_pair = spell_by_key(spell_key)
    if base_pair.nil?
      # Unknown spell: scrolls are still usable as a no-op; potions are not.
      # Unknown spells have no target by default (nothing to validate).
      return nil unless kind == :scroll
      return { kind: :scroll, type: :generic, item_tier: item["bonus"].to_i,
               base_name: nil, variant_name: item["name"], target_mode: "none" }
    end

    base_name, base_data = base_pair
    item_tier = item["bonus"].to_i
    tiers = base_data["tier"].is_a?(Array) ? base_data["tier"] : [base_data["tier"]]
    tier_idx = tiers.index(item_tier) || 0
    tier_val = tiers[tier_idx]
    effect = base_data["effect_hash"] || {}
    variant_name = variant_name_at(base_name, base_data, tier_idx)
    # Potions are always single-target regardless of the underlying spell.
    spell_mode = base_data["target"].to_s
    spell_mode = "single" unless %w[none single multi].include?(spell_mode)
    item_mode = kind == :potion ? "single" : spell_mode
    base = { kind: kind, type: nil, item_tier: item_tier, base_name: base_name,
             variant_name: variant_name, tier_idx: tier_idx, tier_val: tier_val,
             target_mode: item_mode }

    if %w[minor_damage moderate_damage major_damage].any? { |k| effect.key?(k) }
      base.merge(
        type: :cure,
        minor: resolve_effect_value(effect["minor_damage"], tier_idx, tier_val).to_i,
        moderate: resolve_effect_value(effect["moderate_damage"], tier_idx, tier_val).to_i,
        major: resolve_effect_value(effect["major_damage"], tier_idx, tier_val).to_i,
        saturation: resolve_effect_value(effect["saturation"], tier_idx, tier_val).to_i,
        minimum_saturation: resolve_effect_value(effect["minimum_saturation"], tier_idx, tier_val).to_i
      )
    elsif effect.key?("mana")
      base.merge(
        type: :mana,
        mana: resolve_effect_value(effect["mana"], tier_idx, tier_val).to_i,
        saturation: resolve_effect_value(effect["saturation"], tier_idx, tier_val).to_i,
        minimum_saturation: resolve_effect_value(effect["minimum_saturation"], tier_idx, tier_val).to_i
      )
    elsif effect.key?("temp_hp")
      base.merge(
        type: :ward,
        temp_hp: resolve_effect_value(effect["temp_hp"], tier_idx, tier_val).to_i
      )
    else
      # No recognized effect_hash keys. Scrolls still work as a no-op;
      # potions aren't supported (we don't know how to apply them).
      kind == :scroll ? base.merge(type: :generic) : nil
    end
  end

  def variant_name_at(base_name, spell_data, tier_idx)
    tiers = spell_data["tier"].is_a?(Array) ? spell_data["tier"] : [spell_data["tier"]]
    return base_name unless tiers.length > 1
    if spell_data["prefix"] && spell_data["prefix"][tier_idx]
      "#{spell_data["prefix"][tier_idx]} #{base_name}"
    elsif spell_data["suffix"] && spell_data["suffix"][tier_idx]
      "#{base_name} #{spell_data["suffix"][tier_idx]}"
    else
      base_name
    end
  end

  # Potion saturation: 2 * item_tier, doubled for each step the item tier
  # exceeds the user tier. Tier 0 counts as 0.5 for the base multiplication
  # (per CLAUDE.md), but the step count uses integer tier values. Result floored.
  def self.potion_saturation(item_tier, user_tier)
    base_tier = item_tier.to_i == 0 ? 0.5 : item_tier.to_f
    base = 2 * base_tier
    diff = [item_tier.to_i - user_tier.to_i, 0].max
    (base * (2 ** diff)).floor
  end

  # For a spell variant, return a hash of ward effects (temp hp grant),
  # or nil if the spell has no temp_hp effect_hash key.
  def ward_effects(spell_name)
    resolved = resolve_spell_variant(spell_name)
    return nil unless resolved
    _base, spell_data, idx, tier_val = resolved
    effect = spell_data["effect_hash"] || {}
    return nil unless effect.key?("temp_hp")
    {
      base_name: resolved[0],
      tier_idx: idx,
      tier_val: tier_val,
      temp_hp: resolve_effect_value(effect["temp_hp"], idx, tier_val).to_i
    }
  end

  # For a spell variant, return a hash of cure effects resolved at its tier,
  # or nil if the spell has no healing effect_hash keys.
  def cure_effects(spell_name)
    resolved = resolve_spell_variant(spell_name)
    return nil unless resolved
    _base, spell_data, idx, tier_val = resolved
    effect = spell_data["effect_hash"] || {}
    has_heal = %w[minor_damage moderate_damage major_damage].any? { |k| effect.key?(k) }
    return nil unless has_heal
    {
      base_name: resolved[0],
      tier_idx: idx,
      tier_val: tier_val,
      minor: resolve_effect_value(effect["minor_damage"], idx, tier_val).to_i,
      moderate: resolve_effect_value(effect["moderate_damage"], idx, tier_val).to_i,
      major: resolve_effect_value(effect["major_damage"], idx, tier_val).to_i,
      saturation: resolve_effect_value(effect["saturation"], idx, tier_val).to_i,
      minimum_saturation: resolve_effect_value(effect["minimum_saturation"], idx, tier_val).to_i
    }
  end

  def resolve_effect_value(val, idx, tier_val)
    return nil if val.nil?
    return val[idx] if val.is_a?(Array)
    return eval_tier_formula(val, tier_val) if val.is_a?(String)
    val
  end

  # Per CLAUDE.md: tier 0 counts as 0.5 in all formulas. Result is floored.
  def eval_tier_formula(formula, tier_val)
    effective_tier = tier_val.to_i == 0 ? 0.5 : tier_val.to_f
    result = formula.to_s.gsub("tier", effective_tier.to_s)
    raise "Unsafe formula: #{formula}" unless result.match?(/\A[\d\s+\-*\/().]+\z/)
    eval(result).floor
  end

  def ammunition_store_items
    items = []
    item_costs = @data["item_costs"]
    property_costs = @data["property_costs"] || {}
    ammo_costs = item_costs["ammunition"]
    return items unless ammo_costs.is_a?(Array)

    # Base ammunition at each tier
    ammo_costs.each_with_index do |price, tier|
      items << {
        "name" => tier == 0 ? "Arrows" : "Arrows +#{tier}",
        "price" => price, "type" => "ammunition", "subtype" => "arrow",
        "bonus" => tier, "tier" => tier,
        "properties" => {"consumable" => true},
        "description" => tier == 0 ? "Standard arrows." : "Magical arrows with a +#{tier} enhancement bonus."
      }
    end

    # Property variants
    property_costs.each do |prop_name, prop|
      prop["requirements"].each do |req|
        next unless req["type"] == "ammunition"
        min_tier = req["tier"].to_s.gsub(">=", "").to_i
        ammo_costs.each_with_index do |base_price, tier|
          next if tier < min_tier
          items << {
            "name" => "#{prop_name} Arrows +#{tier}",
            "price" => base_price + prop["cost"],
            "type" => "ammunition", "subtype" => "arrow",
            "bonus" => tier, "tier" => tier,
            "properties" => {"consumable" => true, prop_name.downcase => true},
            "description" => prop["description"]
          }
        end
      end
    end

    items
  end

  def spell_store_items
    items = []
    item_costs = @data["item_costs"]
    @data["spells"].each do |spell_name, spell|
      next unless spell["items"]
      tiers = spell["tier"].is_a?(Array) ? spell["tier"] : [spell["tier"]]
      spell["items"].each do |item_type|
        cost_formula = item_costs[item_type]
        next unless cost_formula
        tiers.each_with_index do |tier_val, idx|
          price = eval(cost_formula.gsub("tier", tier_val.to_s))
          name = spell_item_name(spell_name, spell, idx, tiers.length, item_type)
          desc = resolve_description(spell, idx, tier_val)
          # Wands are not consumable (they have charges, not a single use), so
          # they omit the consumable flag and use "item" as their type.
          type = item_type == "wand" ? "item" : "consumable"
          properties = item_type == "wand" ? {"spell" => spell_name.downcase.gsub(' ', '_')}
                                           : {"consumable" => true, "spell" => spell_name.downcase.gsub(' ', '_')}
          items << {
            "name" => name, "price" => price, "type" => type, "subtype" => item_type,
            "bonus" => 0, "spell" => spell_name.downcase.gsub(' ', '_'), "tier" => tier_val,
            "properties" => properties,
            "description" => desc
          }
        end
      end
    end
    items
  end

  private

  def resolve_description(spell, idx, tier_val)
    spell["description"].gsub(/\{(\w+)\}/) do |match|
      var = $1
      val = spell[var] || (spell["effect_hash"] && spell["effect_hash"][var])
      next match unless val
      if val.is_a?(Array)
        val[idx].to_s
      elsif val.is_a?(String)
        eval(val.gsub("tier", tier_val.to_s)).to_s rescue val
      else
        val.to_s
      end
    end
  end

  def spell_item_name(spell_name, spell, idx, tier_count, item_type)
    if tier_count > 1 && spell["prefix"]
      "#{spell["prefix"][idx]} #{spell_name} #{item_type.capitalize}"
    elsif tier_count > 1 && spell["suffix"]
      "#{spell_name} #{spell["suffix"][idx]} #{item_type.capitalize}"
    else
      "#{spell_name} #{item_type.capitalize}"
    end
  end
end

module Skills
  def self.skill_group(skill, rules); return skill_list(rules).find { |skill_group, attr| skills_match?(skill_group, skill) }[0]; end
  def self.skill_attr(skill, rules); return skill_list(rules)[skill_group(skill, rules)].to_sym; end
  def self.skill_list(rules)
    inverted = {}
    rules["skill"]["skill_list"].each do |attr, skills|
      skills.each { |skill| inverted[skill] = attr }
    end
    inverted
  end
  def self.skills_match?(skill_g, skill); skill_g == skill.to_s || (skill_g.end_with?('_') && skill.to_s.start_with?(skill_g)); end
end

class SingleKlassProgress
  attr_reader :name, :level, :skill_list
  def initialize(klass_data); @name = klass_data['class']; @level = klass_data['level'].to_i; @skill_list = klass_data['skills']; end
  def self.force_values(name, level, skill_list); return SingleKlassProgress.new({"level" => level, "class" => name, "skills" => skill_list}); end

  def save_ranks(attr, rules)
    return ranks(rules["class_advancement"][@name]["saves"][attr.to_s], rules["advancement"]["competency"]["save_ranks_per_level"])
  end

  def is_class_skill(skill, rules); return rules['reference']['class_skills'][@name].include?(Skills.skill_group(skill, rules)); end
  def skill_ranks(skill, rules)
    return 0 unless @skill_list.include?(skill.to_s)
    return ranks(skill_adv_rate(skill,rules), rules["advancement"]["competency"]["skill_ranks_per_level"])
  end

  def bab(rules); return ranks(rules["class_advancement"][@name]["bab"], rules["advancement"]["competency"]["skill_ranks_per_level"]); end

  def mana_max(rules); rules["class_advancement"][@name]["mana"].to_i * @level; end
  def speed_modifiers(rules); (speed_rules(rules)["class"][@name] || []).sum { |level, bonus| @level >= level.to_i ? bonus.to_i : 0}; end
  def ability_list(rules); return rules["reference"]["class_abilities"][@name].select { |level, list| @level >= level.to_i }.values.flatten; end

  def damage_reduction(rules); return ability_list(rules).sum { |ability| calc_ability_bonus(rules, ability, "damage_reduction") }; end
  def damage_resilience(rules); return ability_list(rules).sum { |ability| calc_ability_bonus(rules, ability, "damage_resilience") }; end
  def weapon_attack_bonus(rules); return ability_list(rules).sum { |ability| calc_ability_bonus(rules, ability, "weapon_attack_bonus") }; end
  def skill_bonus(skill, rules); return ability_list(rules).sum { |ability| calc_ability_bonus(rules, ability, skill) }; end
  def save_bonus(attr, rules); return ability_list(rules).sum { |ability| calc_ability_bonus(rules, ability, attr) }; end

  private
  def calc_ability_bonus(rules, ability, var); calc_active_bonus(rules, ability, var) + calc_passive_bonus(rules, ability, var); end
  def calc_active_bonus(rules, ability, var); parse_formula(traverse_hash(rules["reference"]["abilities"], [ability, "active", var])); end
  def calc_passive_bonus(rules, ability, var); parse_formula(traverse_hash(rules["reference"]["abilities"], [ability, "passive", var])); end

  def traverse_hash(hash, key_list)
    return hash if key_list.empty?
    return 0 unless hash[key_list[0]]
    return traverse_hash(hash[key_list[0]], key_list[1..-1])
  end

  def skill_adv_rate(skill, rules); return is_class_skill(skill, rules) ? 3 : 2; end
  def ranks(adv_rate, adv_rules); mod = adv_rules[adv_rate - 1]; return (@level.to_f * mod[0].to_f / mod[1].to_f).to_i; end
  def speed_rules(rules); return rules["reference"]["speed_modifiers"]; end

  def parse_formula(formula)
    return 0 if formula == 0 or formula == nil
    result = formula.dup

    {level: :level}.each do |key, func_sym|
      if func_sym.is_a?(Symbol)
        result.gsub!(key.to_s, send(func_sym).to_s)
      elsif func_sym.is_a?(Integer)
        result.gsub!(key.to_s, func_sym.to_s)
      end
    end

    raise "Unsafe formula: #{result}" unless result.match?(/\A[\d\s+\-*\/().%=?:]+\z/) && !result.match?(/(?<!=)=(?!=)/)
    eval(result)
  end
end

module KlassProgress
  attr_reader :klass_list

  def initialize(character)
    @klass_list = character["classes"].map { |klass_data| SingleKlassProgress.new(klass_data) }
    super(character); rescue ArgumentError
  end

  def level(); @klass_list.sum(&:level); end
  def save_total(attr); return save_ranks(attr) + half_mod(attr); end
  def save_ranks(attr); return @klass_list.sum { |progress| progress.save_ranks(attr, @rules) }; end
  def save_dice(attr); compute_dice(save_ranks(attr), half_mod(attr)); end

  def save_bonus(attr)
    base = compute_bonus(save_ranks(attr), half_mod(attr))
    class_bonus = @klass_list.sum { |progress| progress.save_bonus(attr, @rules) }
    return base + class_bonus
  end

  def clean_skill_name(skill)
    return "Perform Sing (Deception, Sense Motive)" if name == 'Cottonballs' and skill == 'perform_sing'
    return skill.gsub('_', ' ').split(' ').map(&:capitalize).join(' ')
  end

  def get_skill_attr(skill); Skills.skill_attr(skill, @rules); end
  def skill_total(skill); attr = get_skill_attr(skill).to_sym; return skill_ranks(skill) + half_mod(attr); end
  def skill_ranks(skill); return @klass_list.sum { |progress| progress.skill_ranks(skill, @rules) }; end

  def skill_list(); return @klass_list.map { |progress| progress.skill_list }.flatten; end
  def skill_dice(skill); compute_dice(skill_ranks(skill), half_mod(get_skill_attr(skill))); end
  def skill_bonus(skill)
    base = compute_bonus(skill_ranks(skill), half_mod(get_skill_attr(skill)))
    class_bonus = @klass_list.sum { |progress| progress.skill_bonus(skill, @rules) }
    return base + class_bonus
  end

  def bab; return @klass_list.sum { |progress| progress.bab(@rules) }; end
  def bab_total; return bab + half_mod(:dex); end
  def bab_dice; compute_dice(bab, half_mod(:dex)); end
  def bab_bonus; compute_bonus(bab, half_mod(:dex)); end

  def attack_dice(weapon_bonus); compute_dice(bab, half_mod(:dex)); end
  def attack_bonus(weapon_bonus); compute_bonus(bab, half_mod(:dex)) + weapon_bonus; end

  def compute_dice(ranks, half_attr, trained = true)
    sc = @rules["skill"]
    aptitude = ranks + half_attr
    min_dice = trained ? sc["trained_dice_count_minimum"] : sc["untrained_dice_count_minimum"]
    min_dice + (aptitude % sc["dice_count_range"])
  end

  def compute_bonus(ranks, half_attr)
    sc = @rules["skill"]
    aptitude = ranks + half_attr
    (aptitude / sc["dice_count_range"]).to_i + sc["proficiency_bonus_base"]
  end

  def weapon_training_bonus; return @klass_list.sum { |progress| progress.weapon_attack_bonus(@rules) }; end

  def full_klass(); @data["classes"].map { |klass| "#{klass["class"]} #{klass["level"]}" }.join(', '); end
  def mana_max; return @klass_list.sum { |progress| progress.mana_max(@rules) } + (defined?(super) ? super : 0); end

  def speed_modifiers; return @klass_list.sum { |progress| progress.speed_modifiers(@rules) } + (defined?(super) ? super : 0); end
  def ability_list; return @klass_list.map { |progress| progress.ability_list(@rules) }.flatten; end

  def damage_reduction(); return @klass_list.sum { |progress| progress.damage_reduction(@rules) } + (defined?(super) ? super : 0); end
  def damage_resilience(); return @klass_list.sum { |progress| progress.damage_resilience(@rules) } + (defined?(super) ? super : 0); end
end

module BaseStatsMath
  def ability_score_names
    return {"Strength" => :str, "Dexterity" => :dex, "Constitution" => :con, "Intelligence" => :int, "Wisdom" => :wis, "Charisma"=> :cha }
  end

  def str; return @data["ability_scores"]["str"].to_i; end
  def dex; return @data["ability_scores"]["dex"].to_i; end
  def con; return @data["ability_scores"]["con"].to_i; end
  def int; return @data["ability_scores"]["int"].to_i; end
  def wis; return @data["ability_scores"]["wis"].to_i; end
  def cha; return @data["ability_scores"]["cha"].to_i; end
  def initiative; return half_mod(:wis); end
  def score(attr); self.send(attr); end
  def half_mod(attr); (self.send(attr) / 2).to_i; end
  def attr_dice(attr); compute_dice(0, half_mod(attr), false); end
  def attr_bonus(attr); compute_bonus(0, half_mod(attr)); end

  def hp_max; return parse_formula(@rules["advancement"]["natural"]["hp"][tier]); end
  def mana_max; return parse_formula(@rules["advancement"]["natural"]["mana"][tier]) + (defined?(super) ? super : 0); end
  def mana_regen; return (mana_max / 4).to_i; end
end

module TierMath
  def tier; @rules["advancement"]["tier"].find_index { |threshold| level < threshold } || @rules["advancement"]["tier"].length; end
  def tier_damage_reduction(attacker_tier); r = @rules["reference"]["tier"]["damage_reduction"]; [0, r[tier] - r[attacker_tier]].min; end
  def damage_reduction(); return 0; end
  def damage_resilience(); return @rules["reference"]["tier"]["damage_resilience"][tier] + (defined?(super) ? super : 0); end
  def combat_pool
    pool_math = rules["advancement"]["competency"]["combat_pool"][tier]
    combat_pool = pool_math["base"] + (pool_math["inc"] * level)
    combat_pool = pool_math["max"] if combat_pool > pool_math["max"]
    combat_pool + half_mod(:dex)
  end
end

module CharacterEquipment
  attr_reader :item_list, :all_items
  def initialize(character)
    super(character) if defined?(super)
    # item_ids are ephemeral and reflect the array position in equipment.json
    # at load time. They are never persisted -- they exist only so the
    # frontend can reference a specific item within a single request cycle.
    @all_items = Tools.load_json('equipment.json').each_with_index.map { |item, i| item["item_id"] = i + 1; item }
    @inline_items = (character["items"] || []).each_with_index.map do |item, i|
      item.merge(
        "item_id" => -(i + 1),
        "owner_id" => character["id"],
        "equipped" => item.fetch("equipped", true),
        "properties" => item["properties"] || build_item_properties(item)
      )
    end
    refresh_items
  end
  def refresh_items; @item_list = @all_items.select { |item| item["owner_id"].to_i == @id } + @inline_items; end

  WEAPON_DEFAULTS = {
    "falcion" => ["heavy", "slashing"], "scimitar" => ["medium", "slashing"],
    "longsword" => ["medium", "slashing"], "shortsword" => ["light", "piercing"],
    "greataxe" => ["heavy", "slashing"], "greatsword" => ["heavy", "slashing"],
    "mace" => ["medium", "bludgeoning"], "warhammer" => ["medium", "bludgeoning"]
  }.freeze

  def build_item_properties(item)
    props = {}
    subtype = item["subtype"].to_s
    case item["type"]
    when "weapon"
      template = @all_items.find { |eq| eq["type"] == "weapon" && eq["subtype"] == subtype }
      props["details"] = template ? (template.dig("properties", "details") || []) : (WEAPON_DEFAULTS[subtype] || [])
    when "shield"
      props["details"] = []
    end
    props
  end
  def equip_search(params = {}); return @item_list.select { |item| params.map { |key, value| item[key] == value }.all? }; end

  def defined_items; return @item_list.select { |item| item["description"] }; end
  def weapon_list; return @item_list.select { |item| item["type"] == "weapon" }; end
  def shield_list; return @item_list.select { |item| item["type"] == "shield" }; end
  def equipped_list; return @item_list.select { |item| item["equipped"] == true }; end
  def ammunition; return @item_list.select { |item| item["properties"]["ammunition"] == true }; end
  def consumable; return @item_list.select { |item| item["properties"]["consumable"] == true }; end
  def other_items
    item_list = @item_list.select do |item|
      (item["properties"]["consumable"] != true && item["properties"]["ammunition"] != true &&
        item["equipped"] != true && !item["description"])
    end
    return item_list
  end

  def item_spell_list
    return_val = {}
    all = @item_list.select { |item| item['properties']['spell'] }

    ['wand', 'scroll'].each do |cat|
      found = all.select { |item| item['subtype'] == cat }
      all = all - found
      return_val[cat] = found.map { |item| item['properties']['spell'].gsub('_', ' ').split(' ').map(&:capitalize).join(' ') } unless found.empty?
    end
    return_val['other'] = all.map { |item| item['properties']['spell'].gsub('_', ' ').split(' ').map(&:capitalize).join(' ') } unless all.empty?

    return false if return_val == {}
    return return_val
  end

  def weapon_speed(weapon_data); (weapon_data["properties"]["details"] || []).sum { |detail| @rules["reference"]["weapon_speed"][detail].to_i }; end
  def weapon_arm_speed(weapon_data); return ((weapon_data["properties"]["details"] || []).include?("ranged")) ? "+1" : ""; end
  def weapon_dmg(weapon_data)
    weight = weapon_data["properties"]["details"] & ['heavy', 'medium', 'light']
    return '-' if weight == [] or weight == false
    return parse_formula(@rules["reference"]["weapon_dmg"][weight.first])
  end
  def weapon_threshold(weapon_data)
    dmg_type = weapon_data["properties"]["details"] & ["bludgeoning", "slashing", "piercing"]
    return '-' if dmg_type == [] or dmg_type == false
    return @rules["reference"]["weapon_threshold"][dmg_type.first]
  end
  def weapon_bleed(weapon_data)
    dmg_type = weapon_data["properties"]["details"] & ["bludgeoning", "slashing", "piercing"]
    return '-' if dmg_type == [] or dmg_type == false
    return @rules["reference"]["weapon_bleed"][dmg_type.first]
  end

  def weapon_dice(weapon_data); attack_dice(weapon_data["bonus"]); end
  def weapon_attack_bonus(weapon_data); attack_bonus(weapon_data["bonus"]); end

  def shield_dice(shield_data); attack_dice(shield_data["bonus"]); end
  def shield_attack_bonus(shield_data); attack_bonus(shield_data["bonus"]); end
  def shield_speed(shield_data); @rules["reference"]["weapon_speed"][shield_data["subtype"]].to_i; end

  def damage_reduction()
    armor = find_item("armor");
    dr = armor ? {"light" => 1, "medium" => 3, "heavy" => 6}[armor["subtype"]].to_i + armor["bonus"].to_i : 0
    return dr + (defined?(super) ? super : 0)
  end

  def damage_resilience()
    armor = find_item("armor");
    dr = armor ? {"light" => 1, "medium" => 2, "heavy" => 3}[armor["subtype"]].to_i * armor["bonus"].to_i : 0
    return dr + (defined?(super) ? super : 0)
  end

  private
  def find_item(type); return @item_list.find { |item| item["type"] == type }; end
end

module CharacterNotes
  attr_reader :note_list
  def initialize(character); super(character) if defined?(super); @note_list = Tools.load_json('notes.json').select { |note| note['owner_id'] == @id}; end
end

class CharacterSheet
  include TierMath
  include KlassProgress
  include BaseStatsMath
  include CharacterEquipment
  include CharacterNotes
  attr_reader :rules, :id, :data

  def initialize(character)
    @rules = Tools.load_json('rules.json')
    classes_data = Tools.load_json('classes.json')
    inject_class_data(classes_data)
    @id = character["id"]
    @data = character
    super(character)
  end

  def inject_class_data(classes_data)
    class_advancement = {}
    class_abilities = {}
    class_skills = {}
    classes_data.each do |name, data|
      class_advancement[name] = data["advancement"] if data["advancement"]
      class_abilities[name] = data["ability_progression"] || {}
      class_skills[name] = data["class_skills"] || []
      (data["sub_class"] || {}).each do |sub_name, sub_data|
        merged_adv = (data["advancement"] || {}).merge(sub_data["advancement"] || {})
        class_advancement[sub_name] = merged_adv
        merged_abilities = (data["ability_progression"] || {}).merge(sub_data["ability_progression"] || {}) { |_key, parent, child| (parent + child).uniq }
        class_abilities[sub_name] = merged_abilities
        class_skills[sub_name] = (data["class_skills"] || []) + (sub_data["class_skills"] || [])
      end
    end
    @rules["class_advancement"] = class_advancement
    @rules["reference"] ||= {}
    @rules["reference"]["class_abilities"] = class_abilities
    @rules["reference"]["class_skills"] = class_skills
  end

  def name; @data["name"]; end
  def player; @data["player"]; end
  def deity; @data["deity"]; end
  def race; @data["race"].reverse.join(' ').capitalize; end
  def race_sym; return (@data["race"][0] || @data["race"]).to_sym; end
  def undead?; @data["race"].include?("undead"); end
  def speed; return 30 + @rules["reference"]["speed_modifiers"]["race"][race_sym.to_s].to_i + speed_modifiers; end

  def con; undead? ? cha_raw : super; end
  def cha_raw; @data["ability_scores"]["cha"].to_i; end

  def tier; @data["tier"] || super; end

  def speed_modifiers; return 0 + super; end
  def mana_max; return 0 + super; end
  def hp_max; super + race_ability_bonus("hp_bonus"); end
  def damage_reduction(); race_ability_bonus("damage_reduction") + super; end
  def damage_resilience(); race_ability_bonus("damage_resilience") + super; end

  def weapon_attack_bonus(weapon_data); super + weapon_training_bonus; end

  def add_plus(func, params = nil); r = params ? send(func, params) : send(func); return "#{'+' if r >= 0}#{r}"; end

  def spell_list; return @data["spells"]; end

  NATURAL_WEAPONS = %w[bite claws slam].freeze

  def race_abilities
    char_abilities = (@data["abilities"] || {}).values.flatten.map { |a| a.downcase.gsub(' ', '_') }
    race_name = @data["race"][0]
    creature_name = @data["name"].downcase
    tier_prog = @rules.dig("reference", "race", "tier_progression", race_name) ||
                @rules.dig("reference", "race", "tier_progression", creature_name) || {}
    race_tier_abilities = tier_prog.select { |t, _| tier >= t.to_i }.values.flatten
    (char_abilities + race_tier_abilities).uniq
  end
  def ability_list; race_abilities + super; end

  def natural_weapons
    weapon_props = @rules["reference"]["natural_weapons"]
    race_abilities.select { |a| weapon_props.key?(a) }.each_with_index.map do |ability_name, i|
      {
        "item_id" => -(1000 + i),
        "name" => ability_name.capitalize,
        "type" => "weapon",
        "subtype" => ability_name,
        "bonus" => 0,
        "equipped" => true,
        "properties" => { "details" => weapon_props[ability_name], "natural" => true }
      }
    end
  end

  def weapon_list; super + natural_weapons; end

  def combat_pool
    pool = super
    pool = (pool / 2).to_i if has_race_ability?("staggered")
    pool
  end

  def initiative_die_bonus
    race_ability_bonus("initiative_bonus")
  end

  def ability_proficiency(ability_name)
    formula = @rules["reference"]["abilities"].dig(ability_name, "proficiency")
    return nil unless formula
    total = parse_formula(formula)
    sc = @rules["skill"]
    dice = sc["untrained_dice_count_minimum"] + (total % sc["dice_count_range"])
    bonus = (total / 5) + tier - 1
    { total: total, dice: dice, bonus: bonus }
  end

  def combat_status
    @combat_status ||= begin
      combat_data = Tools.load_json('combat.json')
      participant = (combat_data['participants'] || []).find { |p| (p['char_id'] || p['id']) == @id }
      if participant
        {
          minor_damage: participant['minor_damage'].to_i,
          moderate_damage: participant['moderate_damage'].to_i,
          major_damage: participant['major_damage'].to_i,
          current_mana: participant['mana'].to_i,
          temporary_hit_points: participant['temporary_hit_points'].to_i
        }
      else
        { minor_damage: 0, moderate_damage: 0, major_damage: 0, current_mana: mana_max, temporary_hit_points: 0 }
      end
    end
  end

  def current_hp; hp_max - combat_status[:minor_damage] - combat_status[:moderate_damage] - combat_status[:major_damage] + combat_status[:temporary_hit_points]; end
  def current_mana; combat_status[:current_mana]; end
  def minor_damage; combat_status[:minor_damage]; end
  def moderate_damage; combat_status[:moderate_damage]; end
  def major_damage; combat_status[:major_damage]; end
  def temporary_hit_points; combat_status[:temporary_hit_points]; end

  private

  def has_race_ability?(name); race_abilities.include?(name); end

  def race_ability_bonus(var)
    abilities_ref = @rules["reference"]["abilities"]
    race_abilities.sum do |ability|
      val = abilities_ref.dig(ability, "passive", var)
      val ? val.to_i : 0
    end
  end

  def parse_formula(formula, params = {})
    result = formula.dup
    func_hash = params.dup.merge({level: level, str: :str, dex: :dex, con: :con, int: :int, wis: :wis, cha: :cha})

    func_hash.each do |key, func_sym|
      if func_sym.is_a?(Symbol)
        result.gsub!(key.to_s, send(func_sym).to_s)
      elsif func_sym.is_a?(Integer)
        result.gsub!(key.to_s, func_sym.to_s)
      end
    end

    raise "Unsafe formula: #{result}" unless result.match?(/\A[\d\s+\-*\/().%=?:]+\z/) && !result.match?(/(?<!=)=(?!=)/)
    eval(result)
  end
end
