require_relative '../lib/skills'
require_relative '../lib/dice_system'
require_relative '../lib/character'
require_relative '../lib/advancement'

DICE_CONFIG_PATH = File.expand_path('../data/dice_resolution.yaml', __dir__)
SKILLS_CONFIG_PATH = File.expand_path('../data/skills.yaml', __dir__)

RSpec.describe Skills do
  let(:dice_system) { DiceSystem.new(DICE_CONFIG_PATH) }

  let(:skills_config) do
    {
      'skills' => {
        'athletics'    => { 'attribute' => 'str' },
        'acrobatics'   => { 'attribute' => 'dex' },
        'martial'      => { 'attribute' => 'dex', 'mandatory' => true },
        'sense_motive' => { 'attribute' => 'wis' },
        'deception'    => { 'attribute' => 'cha' },
        'persuasion'   => { 'attribute' => 'cha' },
        'perform_'     => { 'attribute' => 'cha', 'set' => true }
      },
      'skill_prowess' => { 'attribute_contribution_divisor' => 2 },
      'versatile_performance' => {
        'ability_name' => 'versatile_performance',
        'performances' => {
          'oratory' => %w[persuasion sense_motive],
          'sing'    => %w[deception sense_motive],
          'dance'   => %w[acrobatics athletics]
        }
      }
    }
  end

  let(:skills) { Skills.new(config: skills_config, dice_system: dice_system) }

  let(:advancement_class_definitions) do
    {
      'bard' => {
        'class_skills' => %w[perform_ persuasion sense_motive deception],
        'abilities' => Advancement.normalize_abilities_list([
          { 'name' => 'versatile_performance' }
        ])
      }
    }
  end

  def build_character(attributes:, classes:, chosen_skills: {}, versatile_performance: nil)
    advancement = Advancement.new(
      class_levels:        classes,
      class_skill_choices: chosen_skills,
      class_definitions:   advancement_class_definitions,
      skill_definitions:   skills_config['skills'],
      ability_sub_choices: versatile_performance ? { 'versatile_performance' => versatile_performance } : {}
    )
    character = Character.new(
      id:           1,
      name:         'Test',
      player:       'GM',
      race:         'human',
      attributes:   attributes,
      advancement:  advancement
    )
    [character, advancement]
  end

  describe '#attribute_for' do
    it 'returns the attribute key declared in the catalog' do
      expect(skills.attribute_for('athletics')).to eq('str')
    end

    it 'resolves Skill Set Members through their parent Set' do
      expect(skills.attribute_for('perform_oratory')).to eq('cha')
    end

    it 'raises on unknown skills' do
      expect { skills.attribute_for('telepathy') }.to raise_error(ArgumentError)
    end
  end

  describe '#skill_details' do
    it 'composes Skill Prowess from Ranks plus floor(attribute / 2)' do
      character, advancement = build_character(
        attributes:    { 'str' => 14, 'dex' => 10, 'con' => 10, 'int' => 10, 'wis' => 10, 'cha' => 10 },
        classes:       { 'bard' => 3 },
        chosen_skills: { 'bard' => %w[athletics] }
      )
      ranks = advancement.skill_ranks['athletics']
      details = skills.skill_details('athletics', character, advancement)
      # Prowess = ranks + 14/2 = ranks + 7.
      expect(details['name']).to eq('athletics')
      expect(details['ranks']).to eq(ranks)
      expect(details['prowess']).to eq(ranks + 7)
      expect(details['bonuses']).to have_key('Competency Bonus')
      expect(details['dice_count'] + details['bonuses']['Competency Bonus'] + details['starting_value']).to eq(6 + details['prowess'])
    end

    it 'rejects rolling a bare Skill Set' do
      character, advancement = build_character(
        attributes: { 'str' => 10, 'dex' => 10, 'con' => 10, 'int' => 10, 'wis' => 10, 'cha' => 10 },
        classes:    { 'bard' => 1 }
      )
      expect { skills.skill_details('perform_', character, advancement) }.to raise_error(ArgumentError)
    end

    context 'with Versatile Performance' do
      it 'returns the perform skill details when the performance has higher prowess' do
        # Wis is low, Cha is high — perform_oratory should outscore sense_motive.
        character, advancement = build_character(
          attributes: { 'str' => 10, 'dex' => 10, 'con' => 10, 'int' => 10, 'wis' => 8, 'cha' => 18 },
          classes:    { 'bard' => 5 },
          chosen_skills: { 'bard' => %w[perform_oratory sense_motive] },
          versatile_performance: ['oratory']
        )

        sense_direct = skills.send(:compute_details, 'sense_motive', character, advancement)
        oratory_direct = skills.send(:compute_details, 'perform_oratory', character, advancement)
        expect(oratory_direct['prowess']).to be > sense_direct['prowess']

        details = skills.skill_details('sense_motive', character, advancement)
        expect(details['name']).to eq('sense_motive')
        expect(details['prowess']).to eq(oratory_direct['prowess'])
        expect(details['ranks']).to eq(oratory_direct['ranks'])
      end

      it 'leaves the requested skill alone when its prowess is higher' do
        character, advancement = build_character(
          attributes: { 'str' => 10, 'dex' => 10, 'con' => 10, 'int' => 10, 'wis' => 18, 'cha' => 8 },
          classes:    { 'bard' => 5 },
          chosen_skills: { 'bard' => %w[sense_motive] },
          versatile_performance: ['oratory']
        )
        details = skills.skill_details('sense_motive', character, advancement)
        direct  = skills.send(:compute_details, 'sense_motive', character, advancement)
        expect(details['prowess']).to eq(direct['prowess'])
      end

      it 'ignores performances the character did not choose' do
        # Character has VP with `sing` chosen, asking about persuasion
        # which `sing` does not cover (oratory does, but it isn't chosen).
        character, advancement = build_character(
          attributes: { 'str' => 10, 'dex' => 10, 'con' => 10, 'int' => 10, 'wis' => 10, 'cha' => 18 },
          classes:    { 'bard' => 5 },
          chosen_skills: { 'bard' => %w[persuasion perform_sing] },
          versatile_performance: ['sing']
        )
        details = skills.skill_details('persuasion', character, advancement)
        direct  = skills.send(:compute_details, 'persuasion', character, advancement)
        expect(details['prowess']).to eq(direct['prowess'])
      end

      it 'does nothing when the character lacks Versatile Performance entirely' do
        character, advancement = build_character(
          attributes: { 'str' => 10, 'dex' => 10, 'con' => 10, 'int' => 10, 'wis' => 8, 'cha' => 18 },
          classes:    { 'bard' => 0 },
          chosen_skills: { 'bard' => %w[perform_oratory] }
        )
        details = skills.skill_details('sense_motive', character, advancement)
        direct  = skills.send(:compute_details, 'sense_motive', character, advancement)
        expect(details['prowess']).to eq(direct['prowess'])
      end
    end
  end
end
