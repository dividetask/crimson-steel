require 'dice_resolution'

# Predetermined outcomes for the rolls the server makes.
#
# A browser test states what the dice do rather than hoping — "Thora
# Stoneveil rolls the highest Initiative, the Ogre Brute second". The
# dice the *browser* rolls are scripted from the page (see
# public/js/randomRng.js); this is the other half: the rolls the server
# makes on its own, where no page is involved.
#
# Off unless CRIMSON_TEST_MODE is set. With it unset every method here
# returns nothing and the server rolls normally, so nothing changes for a
# real session. The routes that arm it (lib/routes/test_control.rb) are
# not even mounted.
#
# See docs/project/browser_tests.md.
module TestControl
  module_function

  def enabled?
    !ENV['CRIMSON_TEST_MODE'].to_s.empty?
  end

  # Initiative Strings to hand out instead of rolling, keyed by Creature
  # name or Creature id: { "Thora Stoneveil" => "XX9853" }.
  def initiative
    @initiative ||= {}
  end

  # Seed for the next Random Encounter Table roll, so a table's `1d3 + 1`
  # lands on the same count every run. nil rolls freely.
  def encounter_seed
    @encounter_seed
  end

  def encounter_seed=(value)
    @encounter_seed = value.nil? ? nil : Integer(value)
  end

  # Queue outcomes. Keys are optional; an absent key leaves that source
  # alone, and an explicit null clears it.
  def arm(payload)
    if payload.key?('initiative')
      @initiative = (payload['initiative'] || {}).transform_keys(&:to_s)
                                                 .transform_values { |v| normalize_initiative(v) }
    end
    self.encounter_seed = payload['encounter_seed'] if payload.key?('encounter_seed')
    self
  end

  def reset!
    @initiative = {}
    @encounter_seed = nil
    self
  end

  # The `prerolled_initiatives` map Encounter::State#reroll_initiative
  # takes, resolved from Creature names to Combatant ids against the
  # roster it is about to roll. Empty unless armed.
  def prerolled_initiatives(state, creature_name: nil)
    return {} if !enabled? || initiative.empty?
    state.combatants.each_with_object({}) do |combatant, out|
      key = initiative.keys.find do |k|
        k == combatant[:creature_id].to_s ||
          k == (creature_name ? creature_name.call(combatant[:creature_id]) : nil)
      end
      out[combatant[:id]] = initiative[key] if key
    end
  end

  # An Initiative String is sorted descending, so a test may write the
  # dice in any order.
  def normalize_initiative(value)
    Encounter::Initiative.normalize_string(value)
  rescue StandardError
    value.to_s
  end
end
