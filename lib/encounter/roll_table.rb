require 'abilities'

module Encounter
  # Combat Roll Table resolution. An Ability that fires on a table
  # (talents.yaml `roll_table:`, e.g. Kesser's Gambit → the Kesser
  # Reversal Table) rolls a die here and reports the matched entry.
  #
  # This module owns only the *roll*: given a provided table it picks a
  # face and returns the entry. Resource spending (the channeler's
  # Combat Pool dice + Mana) lives in Encounter::State#use_roll_table_payload,
  # mirroring how Encounter::Special pairs with #use_special_payload.
  # The mechanical effect is the DM's to adjudicate — see
  # `docs/common/ui/encounter_roll_table_stub.md`.
  module RollTable
    module_function

    # Roll on a provided Roll Table (an Abilities catalog Roll Table
    # Hash: { 'die' =>, 'entries' => { face => { 'name' =>, 'effect' => } } }).
    #
    # `face` forces the result — used by the Stub to report a die the
    # DM rolled client-side, and by tests; otherwise the injected `rng`
    # rolls 1..die. `successes` is the channeler's Channel Successes,
    # echoed back so the Stub can scale the entry. Returns nil for an
    # unknown/empty table or an out-of-range face.
    def roll(table, face: nil, successes: 0, rng: Random.new)
      return nil unless table.is_a?(Hash)
      die = table['die'].to_i
      return nil unless die.positive?
      f = face.nil? ? rng.rand(die) + 1 : Integer(face)
      return nil unless f.between?(1, die)
      row = (table['entries'] || {})[f]
      return nil unless row.is_a?(Hash)
      { die: die, face: f, name: row['name'].to_s, effect: row['effect'].to_s,
        successes: successes.to_i }
    end

    # Roll on a Roll Table named through the Abilities catalog.
    def roll_named(name, face: nil, successes: 0, rng: Random.new)
      roll(Abilities.roll_table(name), face: face, successes: successes, rng: rng)
    end
  end
end
