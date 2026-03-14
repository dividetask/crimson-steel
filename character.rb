require_relative 'tools'

class CombatTurn
  attr_reader :rules, :character, :combat_id, :initiative, :mana, :combat_pool, :minor_damage, :moderate_damage, :major_damage, :saturation

  def initialize(combat_turn, character)
    @rules = Tools.load_json('rules.json')
    @combat_id = combat_turn['id']
    @char_id = combat_turn['char_id'] || combat_turn['id']
    @initiative, @mana, @combat_pool = combat_turn['initiative'], combat_turn['mana'], combat_turn['combat_pool']
    @minor_damage, @moderate_damage, @major_damage = combat_turn['minor_damage'], combat_turn['moderate_damage'], combat_turn['major_damage']
    @saturation = combat_turn['saturation']
    @character = CharacterSheet.new(character)
  end

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
      'saturation' => @saturation}
  end

  def hp; return @character.hp_max - @minor_damage - @moderate_damage - @major_damage; end

  def display_name(suffix = nil)
    suffix ? "#{@character.name} ##{suffix}" : @character.name
  end
end

class Combat
  attr_reader :combat_turn_list, :current_turn_id, :current_action, :current_actor_turn_id, :current_action_tool_id, :target_id, :action_params

  def initialize
    character_list = Tools.load_json('characters.json')
    combat_data = Tools.load_json('combat.json')
    @current_turn_id = combat_data['current_turn_id'] || 0
    @current_action = combat_data['current_action'] || ''
    @current_actor_turn_id = combat_data['current_actor_turn_id'] || 0
    @current_action_tool_id = combat_data['current_action_tool_id'] || ''
    @target_id = combat_data['target_id'] || 0
    @action_params = combat_data['action_params'] || {}
    @combat_turn_list = combat_data['participants'].map do |combat_turn|
      char_id = combat_turn['char_id'] || combat_turn['id']
      CombatTurn.new(combat_turn, character_list.find { |c| c["id"] == char_id })
    end
    sort_init
  end

  def current_turn_character; @combat_turn_list[@current_turn_id]; end

  def display_name(combat_turn)
    char_id = combat_turn.character.id
    same = @combat_turn_list.select { |ct| ct.character.id == char_id }
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

  def self.clear_action
    combat_data = Tools.load_json('combat.json')
    combat_data['current_action'] = ''
    combat_data['current_actor_turn_id'] = 0
    combat_data['current_action_tool_id'] = ''
    combat_data['target_id'] = 0
    combat_data['action_params'] = {}
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
          items << {
            "name" => name, "price" => price, "type" => "consumable", "subtype" => item_type,
            "bonus" => 0, "spell" => spell_name.downcase.gsub(' ', '_'), "tier" => tier_val,
            "properties" => {"consumable" => true, "spell" => spell_name.downcase.gsub(' ', '_')},
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
  def self.skill_list(rules); rules["reference"]["skill_list"]; end
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
  def save_dice(attr); parse_formula(@rules["reference"]["skill_dice"], {"ranks" => save_ranks(attr), "half_attr" => half_mod(attr)}); end

  def save_bonus(attr)
    base = parse_formula(@rules["reference"]["skill_bonus"], {"ranks" => save_ranks(attr), "half_attr" => half_mod(attr)})
    class_bonus = @klass_list.sum { |progress| progress.save_bonus(attr, @rules) }
    return base + class_bonus
  end

  def clean_skill_name(skill)
    return "Perform Sing (Deception, Sense Motive)" if name == 'Cottonballs' and skill == 'perform_sing'
    return skill.gsub('_', ' ').split(' ').map(&:capitalize).join(' ')
  end

  def get_skill_attr(skill); return @rules["reference"]["skill_list"][Skills.skill_group(skill, rules)].to_sym; end
  def skill_total(skill); attr = get_skill_attr(skill).to_sym; return skill_ranks(skill) + half_mod(attr); end
  def skill_ranks(skill); return @klass_list.sum { |progress| progress.skill_ranks(skill, @rules) }; end

  def skill_list(); return @klass_list.map { |progress| progress.skill_list }.flatten; end
  def skill_dice(skill); parse_formula(@rules["reference"]["skill_dice"], {"ranks" => skill_ranks(skill), "half_attr" => half_mod(get_skill_attr(skill))}); end
  def skill_bonus(skill)
    base = parse_formula(@rules["reference"]["skill_bonus"], {"ranks" => skill_ranks(skill), "half_attr" => half_mod(get_skill_attr(skill))})
    class_bonus = @klass_list.sum { |progress| progress.skill_bonus(skill, @rules) }
    return base + class_bonus
  end

  def bab; return @klass_list.sum { |progress| progress.bab(@rules) }; end
  def bab_total; return bab + half_mod(:dex); end
  def bab_dice; parse_formula(@rules["reference"]["skill_dice"], {"ranks" => bab, "half_attr" => half_mod(:dex)}); end
  def bab_bonus; parse_formula(@rules["reference"]["skill_bonus"], {"ranks" => bab, "half_attr" => half_mod(:dex)}); end

  def attack_dice(weapon_bonus); parse_formula(@rules["reference"]["skill_dice"], {"ranks" => bab, "half_attr" => half_mod(:dex)}); end
  def attack_bonus(weapon_bonus); parse_formula(@rules["reference"]["skill_bonus"], {"ranks" => bab, "half_attr" => half_mod(:dex)}) + weapon_bonus; end

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
  def attr_dice(attr); parse_formula(@rules["reference"]["skill_dice"], {"ranks" => 0, "half_attr" => half_mod(attr)}); end
  def attr_bonus(attr); parse_formula(@rules["reference"]["skill_bonus"], {"ranks" => 0, "half_attr" => half_mod(attr)}); end

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
    @all_items = Tools.load_json('equipment.json')
    @inline_items = (character["items"] || []).each_with_index.map do |item, i|
      item.merge(
        "item_id" => item["item_id"] || -(i + 1),
        "owner_id" => character["id"],
        "equipped" => item.fetch("equipped", true),
        "properties" => item["properties"] || build_item_properties(item)
      )
    end
    refresh_items
  end
  def refresh_items; @item_list = @all_items.select { |item| item["owner_id"].to_i == @id } + @inline_items; end

  def build_item_properties(item)
    props = {}
    subtype = item["subtype"].to_s
    case item["type"]
    when "weapon"
      props["details"] = @rules["reference"]["weapon_properties"][subtype] || []
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
        merged_abilities = (data["ability_progression"] || {}).merge(sub_data["ability_progression"] || {})
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
  def damage_reduction(); race_ability_bonus("damage_reduction") + super; end
  def damage_resilience(); race_ability_bonus("damage_resilience") + super; end

  def add_plus(func, params = nil); r = params ? send(func, params) : send(func); return "#{'+' if r >= 0}#{r}"; end

  def spell_list; return @data["spells"]; end

  NATURAL_WEAPONS = %w[bite claws slam].freeze

  def race_abilities; (@data["abilities"] || {}).values.flatten.map { |a| a.downcase.gsub(' ', '_') }; end
  def ability_list; race_abilities + super; end

  def natural_weapons
    weapon_props = @rules["reference"]["weapon_properties"]
    race_abilities.select { |a| weapon_props.key?(a) }.map do |ability_name|
      key = ability_name
      {
        "name" => ability_name.capitalize,
        "type" => "weapon",
        "subtype" => key,
        "bonus" => 0,
        "equipped" => true,
        "properties" => { "details" => weapon_props[key], "natural" => true }
      }
    end
  end

  def weapon_list; super + natural_weapons; end

  def weapon_dmg(weapon_data)
    return (str / 4).to_i if weapon_data.dig("properties", "natural")
    super
  end

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
    dice = parse_formula(@rules["reference"]["skill_dice"], {"ranks" => 0, "half_attr" => total})
    bonus = (total / 5) + tier - 1
    { total: total, dice: dice, bonus: bonus }
  end

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
