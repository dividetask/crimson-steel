require 'spec_helper'
require 'rack/test'
require_relative '../app'
require 'class_list'

# Compendium "Classes" chapter: base playable classes only (no archetypes,
# no NPC classes), with a PDF-style detail page (proficiencies, skills, a
# level table, and class features) and no prose blurb on the page.
RSpec.describe 'Compendium Classes', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  def get_html(path)
    header 'Host', 'localhost'
    get path
    last_response
  end

  describe 'ClassList.rows' do
    it 'lists base playable classes and excludes archetypes + NPC classes' do
      keys = ClassList.rows.map { |r| r[:key] }
      expect(keys).to include('barbarian', 'bard', 'cleric', 'druid', 'fighter', 'rogue', 'wizard', 'sorcerer', 'monk')
      expect(keys).not_to include('ranger', 'arcane_trickster') # archetypes
      expect(keys).not_to include('warrior', 'feral', 'commoner', 'paragon') # npc_class
    end

    it 'carries a summary for the list only' do
      expect(ClassList.rows.find { |r| r[:key] == 'barbarian' }[:summary]).not_to be_empty
    end

    it 'excludes the barbarian archetypes from the list' do
      keys = ClassList.rows.map { |r| r[:key] }
      expect(keys).not_to include('berserker', 'weretouched_barbarian', 'bloodrager')
    end
  end

  describe 'Barbarian rework + archetypes' do
    def features_of(key)
      ClassList.detail(key) && ClassList.detail(key)[:features].to_h { |g| [g[:level], g[:abilities].map { |a| a[:key] }] }
    end

    it 'no longer grants the base Barbarian Reckless Attacks or Mindless Rage' do
      names = ClassList.detail('barbarian')[:features].flat_map { |g| g[:abilities] }.map { |a| a[:key] }
      expect(names).to include('rage', 'fast_movement', 'uncanny_dodge', 'primal_tenacity')
      expect(names).not_to include('reckless_attacks', 'mindless_rage')
    end

    it 'gives the Berserker archetype Reckless Attacks (L3) and Mindless Rage (L4)' do
      prog = Creatures::Advancement.look_up_class('berserker')['ability_progression']
      expect(prog['3']).to include('reckless_attacks')
      expect(prog['4']).to include('mindless_rage')
    end

    it 'gives the Weretouched Barbarian its lycanthrope features' do
      prog = Creatures::Advancement.look_up_class('weretouched_barbarian')['ability_progression']
      expect(prog['3']).to include('lycanthropic_rage')
      expect(prog['5']).to include('lycanthropic_resistance')
    end

    it 'makes the Bloodrager a 2-mana Unaligned-martial Evocation caster' do
      b = Creatures::Advancement.look_up_class('bloodrager')
      expect(b['martial_advancement']).to eq('unaligned')
      expect(b['mana_per_level']).to eq(2)
      expect(b['aligned_proficiencies']).to include('evocation')
      expect(b['ability_progression']['3']).to include('bloodrager_spellcasting')
    end

    it 'lists the Barbarian archetypes on the base Barbarian page (branch at level 3)' do
      arcs = ClassList.detail('barbarian')[:archetypes].map { |a| a[:key] }
      expect(arcs).to contain_exactly('berserker', 'weretouched_barbarian', 'bloodrager')
    end

    it "shows an archetype's page with parent + archetype features and a parent badge" do
      berserker = ClassList.detail('berserker')
      expect(berserker[:parent_class]).to eq('Barbarian')
      keys = berserker[:features].flat_map { |g| g[:abilities] }.map { |a| a[:key] }
      expect(keys).to include('rage', 'fast_movement', 'reckless_attacks', 'mindless_rage')
      expect(berserker[:archetypes]).to be_empty
    end

    it 'wires the Bloodrager spells like the Bard (per-Tier, from level 3)' do
      prog = ClassList.detail('bloodrager')[:progression]
      by_level = prog.map { |r| [r[:level], r[:spells_by_tier]] }.to_h
      expect(by_level[1]).to eq([0, 0])   # no spellcasting before level 3
      expect(by_level[3]).to eq([3, 1])   # Tier 0 = level, Tier 1 = floor(level/3)
      expect(by_level[6]).to eq([6, 2])
    end

    it 'lists Tier advancement below the table (not in the Special column)' do
      d = ClassList.detail('barbarian')
      expect(d[:tier_advancement]).to eq([{ tier: 1, level: 1 }, { tier: 2, level: 4 }])
      # every class gets it, and it is not baked into the Special column
      expect(ClassList.detail('wizard')[:tier_advancement]).to eq([{ tier: 1, level: 1 }, { tier: 2, level: 4 }])
      expect(d[:progression].flat_map { |r| r[:special] }).not_to include(a_string_matching(/Tier/))
    end
  end

  describe 'Rogue archetypes' do
    it 'lists both Arcane Trickster and Poisoner on the Rogue page' do
      expect(ClassList.detail('rogue')[:archetypes].map { |a| a[:key] }).to contain_exactly('arcane_trickster', 'poisoner')
    end

    it 'shows the Arcane Trickster per-Tier spells from level 3' do
      by_level = ClassList.detail('arcane_trickster')[:progression].to_h { |r| [r[:level], r[:spells_by_tier]] }
      expect(by_level[2]).to eq([0, 0])
      expect(by_level[3]).to eq([3, 3])
      expect(by_level[4]).to eq([4, 3])
      expect(by_level[5]).to eq([4, 4])
    end

    it 'gives the Poisoner its two level-3 features' do
      f = ClassList.detail('poisoner')[:features].flat_map { |g| g[:abilities] }
      names = f.map { |a| a[:name] }
      expect(names).to include('Precise Poisoner (sneak attack)', 'Poison Crafter')
      expect(f.find { |a| a[:key] == 'poison_crafter' }[:description]).to include('simple poison')
    end
  end

  describe 'Cleric + Rogue ability updates' do
    def feature_map(key)
      ClassList.detail(key)[:features].each_with_object({}) do |g, h|
        g[:abilities].each { |a| h[a[:key]] = a }
      end
    end

    it 'drops Combat Healing and grants Destroy Undead at level 5' do
      cleric = ClassList.detail('cleric')
      keys_by_level = cleric[:features].to_h { |g| [g[:level], g[:abilities].map { |a| a[:key] }] }
      expect(keys_by_level[1]).not_to include('combat_healing')
      expect(keys_by_level[1]).to include('see_injury', 'improved_healing', 'domain')
      expect(keys_by_level[5]).to eq(['destroy_undead'])
    end

    it 'gives the new Cleric features descriptions and channel-divinity display names' do
      f = feature_map('cleric')
      expect(f['improved_healing'][:description]).to include('magical saturation')
      expect(f['domain'][:name]).to eq('Domains')
      expect(f['turn_undead'][:name]).to eq('Turn Undead (channel divinity)')
      expect(f['turn_undead'][:description]).to include('panicked')
      expect(f['destroy_undead'][:name]).to eq('Destroy Undead (channel divinity)')
    end

    it 'updates the Rogue features (Sneak Attack, Trapfinding, Danger Sense luck bonus)' do
      f = feature_map('rogue')
      expect(f['sneak_attack'][:description]).to include('flat-footed creatures within 30 feet')
      expect(f['trapfinding'][:description]).to include('every 5 class levels')
      # Danger Sense now grants a Luck-typed resilience bonus (a valid bonus type).
      entry = Abilities.catalog.ability('Danger Sense')
      expect(entry['modifiers'].first['type']).to eq('Luck')
      expect(f['danger_sense'][:description]).to include('luck bonus to your damage resilience')
    end
  end

  describe 'the list view' do
    it 'renders a Classes nav entry and a card per base class' do
      body = get_html('/compendium?view=classes').body
      expect(body).to include('href="/compendium?view=classes"')
      expect(body).to include('data-class-key="barbarian"')
      expect(body).not_to include('data-class-key="ranger"')
      expect(body).not_to include('data-class-key="warrior"')
    end
  end

  describe 'the detail page (/class-detail)' do
    it 'lays out the barbarian like the design doc, with no prose blurb' do
      body = get_html('/class-detail?name=barbarian').body
      expect(body).to include('Proficiencies')
      expect(body).to include('Light armor, medium armor, shields')  # armor
      expect(body).to include('Simple weapons, martial weapons')     # weapons
      expect(body).to include('Strength, Constitution')              # derived good saves
      expect(body).to include('Aligned Skills')
      expect(body).to include('Aligned</th>')                        # rate column, not "Class Skill"
      expect(body).not_to include('Class Skill')
      expect(body).not_to include('Cross Class')
      expect(body).to include('Class Features')
      expect(body).to include('Rage')
      # No authored narrative description / summary on the page.
      expect(body).not_to include('cs-class-detail-summary')
      expect(body).not_to include(ClassList.rows.find { |r| r[:key] == 'barbarian' }[:summary])
    end

    it 'shows the three proficiency-rate columns (Aligned / Unaligned / Opposed)' do
      prog = ClassList.detail('barbarian')[:progression]
      expect(prog.map { |r| r[:aligned]   }).to eq([1, 3, 5, 6, 8])   # 5·level/3
      expect(prog.map { |r| r[:unaligned] }).to eq([1, 2, 3, 4, 5])   # level
      expect(prog.map { |r| r[:opposed]   }).to eq([0, 1, 2, 2, 3])   # 2·level/3
      expect(prog.map { |r| r[:mana] }).to eq([1, 2, 3, 4, 5])        # level * mana_per_level
    end

    it 'shows the bard spells-known-per-Tier progression (levels 1-6)' do
      bard = ClassList.detail('bard')
      expect(bard[:spell_tiers]).to eq([0, 1, 2])
      expect(bard[:progression].map { |r| r[:level] }).to eq([1, 2, 3, 4, 5, 6])
      by_level = bard[:progression].map { |r| r[:spells_by_tier] }
      expect(by_level).to eq([[4, 2, 0], [5, 3, 0], [6, 4, 0], [6, 5, 0], [6, 6, 0], [6, 6, 2]])
    end

    it 'invents no per-Tier spell counts for classes without authored progression' do
      # Cleric / non-casters carry no Spell columns — only a note (cleric) or
      # nothing (barbarian). No numbers are fabricated.
      expect(ClassList.detail('cleric')[:spell_tiers]).to be_nil
      expect(ClassList.detail('cleric')[:spellcasting]).not_to be_empty
      expect(ClassList.detail('barbarian')[:spell_tiers]).to be_nil
      expect(ClassList.detail('barbarian')[:spellcasting]).to be_empty
    end

    it 'uses the corrected Rage description (no con/2 formula text)' do
      rage = ClassList.detail('barbarian')[:features]
                      .flat_map { |g| g[:abilities] }.find { |a| a[:key] == 'rage' }
      expect(rage[:description]).to include('10 turns plus an additional turn per class level')
      expect(rage[:description]).not_to include('constitution/2')
    end

    it 'renders an archetype page (Ranger) but not an NPC-only or unknown key' do
      expect(ClassList.detail('ranger')).not_to be_nil          # archetype — viewable via its parent
      expect(ClassList.detail('warrior')).to be_nil             # NPC-only
      expect(ClassList.detail('nope')).to be_nil                # unknown
      expect(get_html('/class-detail?name=ranger').body).to include('Druid archetype')
      expect(get_html('/class-detail?name=warrior').body).to include('could not be found')
    end
  end
end
