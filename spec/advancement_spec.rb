require 'tmpdir'
require_relative '../lib/advancement'

RSpec.describe Advancement do
  describe '.normalize_abilities_list' do
    it 'leaves a flat list unchanged in shape' do
      raw = [
        { 'name' => 'rage' },
        { 'name' => 'uncanny_dodge', 'min_level' => 2 }
      ]
      result = Advancement.normalize_abilities_list(raw)
      expect(result).to eq([
        { 'name' => 'rage' },
        { 'name' => 'uncanny_dodge', 'min_level' => 2 }
      ])
    end

    it 'applies a sticky min_level to following ability entries' do
      raw = [
        { 'name' => 'rage' },
        { 'min_level' => 2 },
        { 'name' => 'uncanny_dodge' },
        { 'name' => 'primal_tenacity' },
        { 'min_level' => 3 },
        { 'name' => 'mindless_rage' }
      ]
      result = Advancement.normalize_abilities_list(raw)
      expect(result).to eq([
        { 'name' => 'rage' },
        { 'name' => 'uncanny_dodge',  'min_level' => 2 },
        { 'name' => 'primal_tenacity', 'min_level' => 2 },
        { 'name' => 'mindless_rage',   'min_level' => 3 }
      ])
    end

    it 'lets a per-entry value override the rolling sticky' do
      raw = [
        { 'min_level' => 2 },
        { 'name' => 'sticky_two' },
        { 'name' => 'override_five', 'min_level' => 5 },
        { 'name' => 'back_to_two' }
      ]
      result = Advancement.normalize_abilities_list(raw)
      expect(result).to eq([
        { 'name' => 'sticky_two',    'min_level' => 2 },
        { 'name' => 'override_five', 'min_level' => 5 },
        { 'name' => 'back_to_two',   'min_level' => 2 }
      ])
    end

    it 'does not propagate scales_with_level out of context entries' do
      raw = [
        { 'scales_with_level' => true },
        { 'name' => 'foo' },
        { 'name' => 'bar', 'scales_with_level' => true }
      ]
      result = Advancement.normalize_abilities_list(raw)
      expect(result).to eq([
        { 'name' => 'foo' },
        { 'name' => 'bar', 'scales_with_level' => true }
      ])
    end
  end

  describe '#class_level / #character_classes' do
    it 'reports the levels passed in' do
      adv = Advancement.new(class_levels: { 'rogue' => 3, 'wizard' => 2 })
      expect(adv.class_level('rogue')).to eq(3)
      expect(adv.class_level(:wizard)).to eq(2)
      expect(adv.class_level('cleric')).to eq(0)
      expect(adv.character_classes).to contain_exactly('rogue', 'wizard')
    end
  end

  describe '#attribute_bonus' do
    it 'multiplies the per-tier bonus by the tier when given a scalar' do
      adv = Advancement.new(tier: 3, attribute_bonus_per_tier: 1)
      %i[str dex con int wis cha].each do |attr|
        expect(adv.attribute_bonus(attr)).to eq(3)
      end
    end

    it 'sums the first N entries when given a per-tier list' do
      adv = Advancement.new(tier: 3, attribute_bonus_per_tier: [1, 1, 1, 1, 1])
      expect(adv.attribute_bonus(:str)).to eq(3)
    end

    it 'is zero at tier 0 regardless of the rules' do
      adv = Advancement.new(tier: 0, attribute_bonus_per_tier: [5, 5])
      expect(adv.attribute_bonus(:str)).to eq(0)
    end

    it 'adds focused-attribute picks on top of the flat bonus' do
      adv = Advancement.new(
        tier: 3,
        attribute_bonus_per_tier:         [1, 1, 1, 1, 1],
        focused_attribute_bonus_per_tier: [0, 2, 2, 2, 2],
        focused_attribute_count:          2,
        tier_attribute_advancement:       %w[dex con con str]
      )
      # Flat = 3 for everyone. Tier-2 picks (dex, con) +2 each;
      # Tier-3 picks (con, str) +2 each.
      expect(adv.attribute_bonus(:dex)).to eq(3 + 2)
      expect(adv.attribute_bonus(:con)).to eq(3 + 2 + 2)
      expect(adv.attribute_bonus(:str)).to eq(3 + 2)
      expect(adv.attribute_bonus(:int)).to eq(3)
      expect(adv.attribute_bonus(:wis)).to eq(3)
      expect(adv.attribute_bonus(:cha)).to eq(3)
    end

    it 'ignores focused picks past the current tier' do
      adv = Advancement.new(
        tier: 2,
        attribute_bonus_per_tier:         [1, 1, 1, 1, 1],
        focused_attribute_bonus_per_tier: [0, 2, 2, 2, 2],
        focused_attribute_count:          2,
        tier_attribute_advancement:       %w[dex con con str]
      )
      # Only tier-2 picks count.
      expect(adv.attribute_bonus(:str)).to eq(2)
      expect(adv.attribute_bonus(:con)).to eq(2 + 2)
    end
  end

  describe '#tier auto-computation' do
    let(:tier_advancement) { { 'player_character' => [1, 4, 8, 16, 32] } }

    it 'derives the tier from total class level via the breakpoint table' do
      adv = Advancement.new(
        class_levels:     { 'fighter' => 4 },
        tier_advancement: tier_advancement
      )
      expect(adv.tier).to eq(2)
      expect(adv.tier_overridden?).to be(false)
    end

    it 'sums class levels across multiple classes when computing tier' do
      adv = Advancement.new(
        class_levels:     { 'fighter' => 6, 'wizard' => 2 },
        tier_advancement: tier_advancement
      )
      expect(adv.tier).to eq(3) # total 8 -> tier 3
    end

    it 'returns the explicit override when one is provided' do
      adv = Advancement.new(
        tier:             5,
        class_levels:     { 'fighter' => 1 },
        tier_advancement: tier_advancement
      )
      expect(adv.tier).to eq(5)
      expect(adv.tier_overridden?).to be(true)
    end

    it 'uses the breakpoints for the matching tag' do
      adv = Advancement.new(
        tags:             ['common'],
        class_levels:     { 'fighter' => 8 },
        tier_advancement: { 'player_character' => [1, 4, 8, 16, 32], 'common' => [1, 8, 20, 40, 80] }
      )
      expect(adv.tier).to eq(2) # 8 levels => tier 2 on the common track
    end

    it 'picks the highest tier when multiple tags have breakpoint lists' do
      adv = Advancement.new(
        tags:             %w[noble common],
        class_levels:     { 'fighter' => 8 },
        tier_advancement: { 'noble' => [0, 2, 6, 14, 18], 'common' => [0, 8, 12, 20, 40] }
      )
      # noble: 8 >= {0,2,6} -> 3; common: 8 >= {0,8} -> 2
      expect(adv.tier).to eq(3)
    end

    it 'ignores tags that have no breakpoint entry' do
      adv = Advancement.new(
        tags:             %w[player_character ally],
        class_levels:     { 'fighter' => 4 },
        tier_advancement: { 'player_character' => [1, 4, 8, 16, 32] }
      )
      expect(adv.tier).to eq(2)
    end

    it 'falls back to player_character when no tag has an entry' do
      adv = Advancement.new(
        tags:             ['mystery'],
        class_levels:     { 'fighter' => 4 },
        tier_advancement: { 'player_character' => [1, 4, 8, 16, 32] }
      )
      expect(adv.tier).to eq(2)
    end

    it 'is zero when there are no breakpoints and no override' do
      adv = Advancement.new(class_levels: { 'fighter' => 4 })
      expect(adv.tier).to eq(0)
    end
  end

  describe '#abilities' do
    let(:class_definitions) do
      {
        'fighter' => {
          'abilities' => Advancement.normalize_abilities_list([
            { 'name' => 'weapon_training', 'scales_with_level' => true },
            { 'name' => 'armor_training',  'scales_with_level' => true },
            { 'min_level' => 4 },
            { 'name' => 'bonus_feat' }
          ])
        },
        'rogue' => {
          'abilities' => Advancement.normalize_abilities_list([
            { 'name' => 'trapfinding',  'scales_with_level' => true },
            { 'name' => 'sneak_attack', 'scales_with_level' => true },
            { 'name' => 'thieves_cant' },
            { 'min_level' => 2 },
            { 'name' => 'danger_sense' }
          ])
        },
        'wizard' => { 'abilities' => [] },
        'arcane_trickster' => {
          'parent_class' => 'rogue',
          'abilities' => Advancement.normalize_abilities_list([
            { 'min_level' => 3 },
            { 'name' => 'combat_trickery' },
            { 'name' => 'mage_legerdemain' }
          ])
        }
      }
    end

    it "scales an ability's level by the granting class's level" do
      adv = Advancement.new(class_levels: { 'rogue' => 3 }, class_definitions: class_definitions)
      sneak = adv.abilities.find { |a| a.name == 'sneak_attack' }
      expect(sneak.level).to eq(3)
    end

    it 'sums scaling levels across every class that grants the ability' do
      class_definitions['wizard']['abilities'] = Advancement.normalize_abilities_list([
        { 'name' => 'sneak_attack', 'scales_with_level' => true }
      ])
      adv = Advancement.new(
        class_levels:      { 'rogue' => 3, 'wizard' => 2 },
        class_definitions: class_definitions
      )
      expect(adv.abilities.find { |a| a.name == 'sneak_attack' }.level).to eq(5)
    end

    it 'does not pull levels from classes that do not grant the ability' do
      adv = Advancement.new(class_levels: { 'rogue' => 3, 'wizard' => 2 }, class_definitions: class_definitions)
      expect(adv.abilities.find { |a| a.name == 'sneak_attack' }.level).to eq(3)
    end

    it 'omits abilities below their min_level' do
      adv = Advancement.new(class_levels: { 'rogue' => 1 }, class_definitions: class_definitions)
      expect(adv.abilities.map(&:name)).not_to include('danger_sense')
    end

    it 'unlocks abilities once the min_level threshold is met' do
      adv = Advancement.new(class_levels: { 'fighter' => 4 }, class_definitions: class_definitions)
      expect(adv.abilities.map(&:name)).to include('bonus_feat')
    end

    context 'with parent_class archetypes' do
      it "grants the parent class's abilities at the archetype's level" do
        adv = Advancement.new(class_levels: { 'arcane_trickster' => 3 }, class_definitions: class_definitions)
        names = adv.abilities.map(&:name)
        expect(names).to include('sneak_attack', 'trapfinding', 'thieves_cant', 'danger_sense')
        expect(names).to include('combat_trickery', 'mage_legerdemain')
      end

      it "scales a parent ability by the archetype's class level" do
        adv = Advancement.new(class_levels: { 'arcane_trickster' => 3 }, class_definitions: class_definitions)
        expect(adv.abilities.find { |a| a.name == 'sneak_attack' }.level).to eq(3)
      end

      it "sums parent ability levels when the character has both classes" do
        adv = Advancement.new(
          class_levels:      { 'rogue' => 2, 'arcane_trickster' => 3 },
          class_definitions: class_definitions
        )
        expect(adv.abilities.find { |a| a.name == 'sneak_attack' }.level).to eq(5)
      end
    end
  end

  describe '#skill_ranks' do
    let(:class_definitions) do
      {
        'rogue'   => { 'class_skills' => %w[stealth perception perform_], 'opposed_skills' => %w[athletics] },
        'wizard'  => { 'class_skills' => %w[arcana],                       'opposed_skills' => %w[athletics] },
        'fighter' => { 'class_skills' => %w[athletics martial] }
      }
    end

    it 'returns an empty hash when no skills are chosen and none are mandatory' do
      adv = Advancement.new(class_levels: { 'rogue' => 3 }, class_definitions: class_definitions)
      expect(adv.skill_ranks).to eq({})
    end

    it 'uses the class-skill rate for skills the class lists' do
      adv = Advancement.new(
        class_levels:        { 'rogue' => 3 },
        class_skill_choices: { 'rogue'  => %w[stealth] },
        class_definitions:   class_definitions
      )
      # floor(5*3/3) = 5
      expect(adv.skill_ranks).to eq('stealth' => 5)
    end

    it 'uses the opposed-skill rate when the class lists the skill as opposed' do
      adv = Advancement.new(
        class_levels:        { 'rogue' => 3 },
        class_skill_choices: { 'rogue'  => %w[athletics] },
        class_definitions:   class_definitions
      )
      # floor(2*3/3) = 2
      expect(adv.skill_ranks).to eq('athletics' => 2)
    end

    it 'uses the average rate when class_skills is present but the skill is unlisted' do
      adv = Advancement.new(
        class_levels:        { 'wizard' => 4 },
        class_skill_choices: { 'wizard' => %w[stealth] },
        class_definitions:   class_definitions
      )
      expect(adv.skill_ranks).to eq('stealth' => 4)
    end

    it 'uses the average rate for skills explicitly listed in non_class_skills' do
      definitions = {
        'bard' => { 'non_class_skills' => %w[arcana restricted_magic] }
      }
      adv = Advancement.new(
        class_levels:        { 'bard' => 3 },
        class_skill_choices: { 'bard' => %w[arcana] },
        class_definitions:   definitions
      )
      expect(adv.skill_ranks).to eq('arcana' => 3)
    end

    it 'defaults to the class-skill rate when class_skills is omitted entirely' do
      definitions = {
        'bard' => { 'non_class_skills' => %w[arcana] }
      }
      adv = Advancement.new(
        class_levels:        { 'bard' => 3 },
        class_skill_choices: { 'bard' => %w[persuasion] },
        class_definitions:   definitions
      )
      # bard omits class_skills, so any skill not in non_class_skills /
      # opposed_skills is treated as a class skill: floor(5*3/3) = 5
      expect(adv.skill_ranks).to eq('persuasion' => 5)
    end

    it 'sums per-class contributions across multiple classes' do
      adv = Advancement.new(
        class_levels:        { 'rogue' => 3, 'wizard' => 2 },
        class_skill_choices: {
          'rogue'  => %w[perception],
          'wizard' => %w[perception]
        },
        class_definitions:   class_definitions
      )
      # rogue: class skill -> floor(15/3)=5; wizard: average -> 2; total 7
      expect(adv.skill_ranks).to eq('perception' => 7)
    end

    it 'matches a skill set entry by prefix for chosen children' do
      adv = Advancement.new(
        class_levels:        { 'rogue' => 3 },
        class_skill_choices: { 'rogue'  => %w[perform_dance] },
        class_definitions:   class_definitions
      )
      expect(adv.skill_ranks).to eq('perform_dance' => 5)
    end

    it 'auto-advances mandatory skills with the class-skill rate when listed by the class' do
      adv = Advancement.new(
        class_levels:      { 'fighter' => 4 },
        class_definitions: class_definitions,
        skill_definitions: { 'martial' => { 'mandatory' => true } }
      )
      # floor(5*4/3) = 6
      expect(adv.skill_ranks).to eq('martial' => 6)
    end

    it 'auto-advances mandatory skills at the neither rate for classes that do not list them' do
      adv = Advancement.new(
        class_levels:      { 'wizard' => 3 },
        class_definitions: class_definitions,
        skill_definitions: { 'martial' => { 'mandatory' => true } }
      )
      expect(adv.skill_ranks).to eq('martial' => 3)
    end

    it 'sums mandatory skill contributions across classes regardless of choice lists' do
      adv = Advancement.new(
        class_levels:      { 'fighter' => 4, 'wizard' => 3 },
        class_definitions: class_definitions,
        skill_definitions: { 'martial' => { 'mandatory' => true } }
      )
      # fighter class skill: 6; wizard neither: 3; total 9
      expect(adv.skill_ranks).to eq('martial' => 9)
    end
  end

  describe '#save_ranks' do
    let(:class_definitions) do
      {
        'rogue'   => { 'saves' => %w[dex int] },
        'fighter' => { 'saves' => %w[str con] },
        'arcane_trickster' => { 'parent_class' => 'rogue', 'saves' => %w[dex int] }
      }
    end

    it 'uses class-skill rate for specialized saves and opposed-skill rate for the rest' do
      adv = Advancement.new(class_levels: { 'rogue' => 3 }, class_definitions: class_definitions)
      expect(adv.save_ranks).to eq(
        'dex' => 5, 'int' => 5,
        'str' => 2, 'con' => 2, 'wis' => 2, 'cha' => 2
      )
    end

    it 'sums save ranks across multiple classes' do
      adv = Advancement.new(
        class_levels:      { 'rogue' => 3, 'fighter' => 2 },
        class_definitions: class_definitions
      )
      # rogue 3: dex/int specialized -> 5; rest -> 2
      # fighter 2: str/con specialized -> floor(10/3)=3; rest -> floor(4/3)=1
      expect(adv.save_ranks).to eq(
        'dex' => 5 + 1, 'int' => 5 + 1,
        'str' => 2 + 3, 'con' => 2 + 3,
        'wis' => 2 + 1, 'cha' => 2 + 1
      )
    end

    it 'inherits save attributes from a parent class' do
      adv = Advancement.new(
        class_levels:      { 'arcane_trickster' => 4 },
        class_definitions: class_definitions
      )
      # AT 4: dex/int specialized -> floor(20/3)=6; rest -> floor(8/3)=2
      expect(adv.save_ranks).to eq(
        'dex' => 6, 'int' => 6,
        'str' => 2, 'con' => 2, 'wis' => 2, 'cha' => 2
      )
    end
  end

  describe '.split_classes_block' do
    it 'parses integer shorthand and verbose hashes' do
      levels, skills = Advancement.split_classes_block(
        'rogue'  => { 'level' => 3, 'skills' => %w[stealth perception] },
        'wizard' => 2
      )
      expect(levels).to eq('rogue' => 3, 'wizard' => 2)
      expect(skills).to eq('rogue' => %w[stealth perception])
    end
  end

  describe '.from_entry' do
    it 'pulls level + skill choices out of the verbose form' do
      adv = Advancement.from_entry(
        {
          'tier' => 1,
          'classes' => {
            'rogue' => { 'level' => 3, 'skills' => %w[stealth perception] }
          }
        }
      )
      expect(adv.class_level('rogue')).to eq(3)
      expect(adv.chosen_skills_for('rogue')).to eq(%w[stealth perception])
    end
  end

  describe '.load_config' do
    it 'returns the empty shape when the path is missing' do
      expect(Advancement.load_config(nil)).to eq('rules' => {}, 'classes' => {})
    end

    it 'splits rules from classes and normalizes ability sticky context' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'advancement.yaml')
        File.write(path, <<~YAML)
          attribute_bonus_per_tier: 2
          classes:
            barbarian:
              abilities:
                - name: rage
                - min_level: 2
                - name: uncanny_dodge
                - name: primal_tenacity
                - min_level: 3
                - name: mindless_rage
        YAML
        config = Advancement.load_config(path)
        expect(config['rules']).to eq('attribute_bonus_per_tier' => 2)
        expect(config['classes']['barbarian']['abilities']).to eq([
          { 'name' => 'rage' },
          { 'name' => 'uncanny_dodge',   'min_level' => 2 },
          { 'name' => 'primal_tenacity', 'min_level' => 2 },
          { 'name' => 'mindless_rage',   'min_level' => 3 }
        ])
      end
    end
  end
end
