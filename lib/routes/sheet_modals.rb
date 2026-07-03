# Character-Sheet modal fragments: spell descriptions and the Skill list /
# Skill Roll. Each returns a layout-less HTML fragment the sheet's JS injects
# into a modal popup. Visible to both DM and players (the same reference data).

# Spell Detail (abilities_spell_detail_stub.md) — clicking a spell on the
# sheet opens its description. The clicked name may be a base Catalog name or
# a per-Tier Variant name; CreatureSheet's spell index resolves either to its
# Catalog entry + Variant axis, then Abilities resolves the Variant.
get '/spell-detail' do
  requested = params[:name].to_s
  info  = CreatureSheet.spell_info(requested)
  spell = info && (Abilities.lookup(info[:base], axis_index: info[:axis]) rescue nil)
  erb :_spell_detail, layout: false,
      locals: { spell: spell, requested_name: requested }
end

# Spell School description (abilities_config.yaml → Spell Schools) — clicking a
# School on the Spell List opens this in a modal.
get '/spell-school' do
  key = params[:name].to_s
  erb :_spell_school, layout: false,
      locals: { school: key, description: SpellList.school_description(key) }
end

# Skill list — every Skill (trained and untrained) with the Creature's Dice
# Cap + Bonus, reached by clicking the sheet's "Skills" heading.
get '/skills-panel' do
  acc = (Creatures.lookup(params[:creature_id]) rescue nil)
  unless acc
    halt erb(:_skills_panel, layout: false,
             locals: { creature_id: params[:creature_id], creature_name: nil,
                       skills: [], unavailable: true })
  end
  erb :_skills_panel, layout: false,
      locals: { creature_id: acc.id, creature_name: acc.name,
                skills: CreatureSheet.all_skills(acc), unavailable: false }
end

# Skill Roll — the compact Roll stub for one Skill, opened from a Roll button
# in the Skill list. The TN/Bonus handling lives in Dice Resolution; this only
# assembles the Roll hash and renders the compact stub, which POSTs its result
# to the Log after rolling.
get '/skill-roll' do
  acc  = (Creatures.lookup(params[:creature_id]) rescue nil)
  halt 404 unless acc
  roll = CreatureSheet.skill_roll(acc, params[:key])
  halt 404 unless roll
  erb :_compact_roll_stub, layout: false, locals: { roll: roll, creature_id: acc.id }
end
