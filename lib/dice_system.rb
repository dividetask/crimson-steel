require 'yaml'
require 'securerandom'
require 'set'

class DefaultRandomSource
  def rand_int(low, high)
    SecureRandom.random_number(high - low + 1) + low
  end
end

class DiceSystem
  DEFAULT_FAILURE_MODIFIER = -1
  DEFAULT_CRITICAL_MODIFIER = 2

  attr_reader :dice_resolution_config

  def initialize(config_path, random_source: nil)
    @dice_resolution_config = YAML.load_file(config_path)
    @random_source = random_source || DefaultRandomSource.new
  end

  def rand_roll_die
    @random_source.rand_int(1, @dice_resolution_config['Die Size'])
  end

  def rand_roll_dice(dice_count)
    raise ArgumentError, 'dice_count must be >= 1' if dice_count < 1
    Array.new(dice_count) { rand_roll_die }
  end

  def compute_ascending_indices(dice)
    dice.each_with_index.sort_by { |v, _| v }.map { |_, i| i }
  end

  def compute_nudge_effect(initial_value, nudge_amount, tn,
                           failure_modifier: DEFAULT_FAILURE_MODIFIER,
                           critical_modifier: DEFAULT_CRITICAL_MODIFIER)
    die_size = @dice_resolution_config['Die Size']
    initial_contrib = contribution(initial_value, tn, die_size, failure_modifier, critical_modifier)
    nudged_value = [1, [die_size, initial_value + nudge_amount].min].max
    nudged_contrib = contribution(nudged_value, tn, die_size, failure_modifier, critical_modifier)
    nudged_contrib - initial_contrib
  end

  def compute_roll_parameters(modifiers)
    bonus_types = @dice_resolution_config['Bonus Types List'].keys
    accepted_keys = Set.new
    bonus_types.each do |type_name|
      accepted_keys << "#{type_name} Bonus"
      accepted_keys << "#{type_name} Penalty"
      accepted_keys << "#{type_name} Starting"
    end
    modifiers.each_key do |key|
      raise ArgumentError, "Unrecognized modifier key: #{key}" unless accepted_keys.include?(key)
    end
    total_bonus = 0
    total_penalty = 0
    starting_value = 0
    bonus_types.each do |type_name|
      total_bonus += modifiers.fetch("#{type_name} Bonus", 0)
      total_penalty += modifiers.fetch("#{type_name} Penalty", 0)
      starting_value += modifiers.fetch("#{type_name} Starting", 0)
    end
    tn = @dice_resolution_config['Base Target Number'] - total_bonus + total_penalty
    min_tn = @dice_resolution_config['Minimum Target Number']
    max_tn = @dice_resolution_config['Maximum Target Number']
    if tn < min_tn
      starting_value += min_tn - tn
      tn = min_tn
    elsif tn > max_tn
      starting_value -= tn - max_tn
      tn = max_tn
    end
    { 'tn' => tn, 'starting_value' => starting_value }
  end

  # Partition a Skill Prowess (or any Prowess-shaped integer) into
  # a Dice Count, a Competency Bonus, and a Starting Value ready to
  # feed back into compute_roll_parameters / compute_results.
  #
  # Excess Prowess fills dice up to the Maximum Dice Count first,
  # then routes the remaining (signed) Prowess to a Competency
  # modifier. Positive remainder becomes a Competency Bonus;
  # negative remainder becomes a Competency Penalty. Both
  # propagate to Opposed Rolls (with the sign inverted on the
  # opposed side); routing the remainder to Starting Value
  # instead would silently strip that opposed-side effect.
  #
  # No cap on the Bonus or Penalty here. If the Bonus would push
  # the Roll's TN past the Minimum Target Number,
  # `compute_roll_parameters`'s overflow rule converts the
  # excess into Starting Successes downstream — that's where
  # the floor is enforced, not here.
  def compute_check_details(prowess)
    min_dice = @dice_resolution_config['Minimum Dice Count']
    range    = @dice_resolution_config['Dice Count Range']
    max_dice = min_dice + range - 1

    dice_count        = [[min_dice + prowess, max_dice].min, min_dice].max
    remaining         = prowess - (dice_count - min_dice)
    competency_bonus  = [remaining, 0].max
    competency_penalty = [-remaining, 0].max

    {
      'dice_count'         => dice_count,
      'competency_bonus'   => competency_bonus,
      'competency_penalty' => competency_penalty,
      'starting_value'     => 0
    }
  end

  def compute_results(dice, tn, starting_value,
                      failure_modifier: DEFAULT_FAILURE_MODIFIER,
                      critical_modifier: DEFAULT_CRITICAL_MODIFIER)
    die_size = @dice_resolution_config['Die Size']
    dois = starting_value
    critical_count = 0
    dice.each do |value|
      if value == die_size
        critical_count += 1
        dois += critical_modifier
      elsif value >= tn
        dois += 1
      elsif value == 1
        dois += failure_modifier
      end
    end
    { 'degree_of_individual_success' => dois, 'critical_count' => critical_count }
  end

  def apply_nudge(dice, nudge_amount, tn,
                  failure_modifier: DEFAULT_FAILURE_MODIFIER,
                  critical_modifier: DEFAULT_CRITICAL_MODIFIER)
    changes = Array.new(dice.length)
    return changes if nudge_amount == 0 || dice.empty?
    target_index = nil
    target_contrib = nil
    dice.each_with_index do |value, i|
      new_contrib = compute_nudge_effect(value, nudge_amount, tn,
                                         failure_modifier: failure_modifier,
                                         critical_modifier: critical_modifier)
      if target_index.nil?
        target_index = i
        target_contrib = new_contrib
      elsif nudge_amount > 0 && new_contrib > target_contrib
        target_index = i
        target_contrib = new_contrib
      elsif nudge_amount < 0 && new_contrib < target_contrib
        target_index = i
        target_contrib = new_contrib
      end
    end
    die_size = @dice_resolution_config['Die Size']
    target_value = [1, [die_size, dice[target_index] + nudge_amount].min].max
    changes[target_index] = target_value if target_value != dice[target_index]
    changes
  end

  def rand_reroll_some_dice(dice, reroll_count, tn)
    changes = Array.new(dice.length)
    return changes if reroll_count == 0 || dice.empty?
    sorted_indices = compute_ascending_indices(dice)
    remaining = reroll_count.abs
    if reroll_count > 0
      sorted_indices.each do |die_index|
        break if remaining == 0
        break if dice[die_index] >= tn
        changes[die_index] = rand_roll_die
        remaining -= 1
      end
    else
      sorted_indices.reverse_each do |die_index|
        break if remaining == 0
        break if dice[die_index] < tn
        changes[die_index] = rand_roll_die
        remaining -= 1
      end
    end
    changes
  end

  private

  def contribution(value, tn, die_size, failure_modifier, critical_modifier)
    return critical_modifier if value == die_size
    return failure_modifier if value == 1
    return 1 if value >= tn
    0
  end
end
