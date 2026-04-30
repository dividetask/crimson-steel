# Demo data seeding for local development. Loaded by app.rb only when
# Sinatra is running in development mode, so production deployments
# never create these placeholder devices. Safe to re-run — each
# insert is skipped when the device id is already present.
#
# Set RACK_ENV=production (or APP_ENV=production) to suppress.

%w[demo-phone-alice demo-tablet-bob].each do |did|
  USER_STORE.create(did) unless USER_STORE.find(did)
end

# Seed a development Combat so the start-of-turn stub on the test
# page has a current Combatant to operate on. Skips when state has
# already been written (the YAML survives restarts) so the DM's
# in-progress combat isn't clobbered on every reload.
if COMBAT.combatants.empty?
  CHARACTER_REGISTRY.values.first(3).each do |char|
    COMBAT.add_combatant(char_id: char.id, name: char.name)
  end
  COMBAT.reroll_all_initiative
end

# Seed a couple of afflictions on the active combatant so the start-
# of-turn stub has something to roll saves against. Idempotent.
if (active = COMBAT.current_combatant) && CONDITIONS_REGISTRY
  conds = CONDITIONS_REGISTRY.for_character(active['char_id'])
  if conds.afflictions.empty?
    conds.inflict_affliction('bleeding', 8, (CHARACTER_LOOKUP.call(active['char_id'])&.tier || 1))
    conds.inflict_affliction('common_venom', 12, (CHARACTER_LOOKUP.call(active['char_id'])&.tier || 1))
    conds.apply_shock(2)
    conds.apply_acid_damage(4)
    CONDITIONS_REGISTRY.save!
  end
end
