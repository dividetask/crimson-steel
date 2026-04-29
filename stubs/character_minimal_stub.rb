# Compact character card. Modeled on the 5e monster statblock —
# single column, vertical flow, red rules between sections so it
# reads at a glance on a tablet or phone. Use character_full_stub
# when the player needs every dice column / rank / formula.
#
# Reuses character_sheet_dummy_defaults from character_full_stub
# so the fallback values stay in one place.

helpers do
  def character_minimal_stub(character:, dummy: {})
    erb :"stubs/_character_minimal_stub", layout: false, locals: {
      character: character,
      dummy:     character_sheet_dummy_defaults.merge(dummy || {})
    }
  end
end
