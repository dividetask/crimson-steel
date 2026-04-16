require_relative '../templates'
require 'json'

RSpec.describe Templates do
  let(:slaver) do
    {
      'id' => 'slaver',
      'name' => 'Slaver',
      'race' => ['orc'],
      'ability_scores' => {'str' => 17, 'dex' => 11, 'con' => 12, 'int' => 7, 'wis' => 8, 'cha' => 6},
      'classes' => [{'level' => 3, 'class' => 'fighter', 'skills' => ['intimidate']}],
      'variants' => [
        {
          'id' => 'human',
          'chance' => 0.10,
          'overrides' => {
            'race' => ['human'],
            'ability_scores' => {'cha' => '+2', 'int' => '+2'},
            'name' => 'Slaver (Human)'
          },
          'gear_patch' => {'gold' => '10'}
        },
        {
          'id' => 'barbarian',
          'chance' => 0.10,
          'classes_add' => [{'level' => 1, 'class' => 'barbarian', 'skills' => ['athletics']}],
          'name_suffix' => ' (Barb)'
        }
      ],
      'gear' => 'slaver_loot'
    }
  end

  let(:tables) do
    {
      'slaver_loot' => {
        'id' => 'slaver_loot',
        'rolls' => [
          {'slot' => 'weapon', 'item' => {'name' => 'falcion', 'type' => 'weapon'}},
          {
            'slot' => 'armor',
            'options' => [
              {'chance' => 0.90, 'item' => {'name' => 'chain shirt'}},
              {'chance' => 0.05, 'item' => {'name' => 'breastplate'}},
              {'chance' => 0.05, 'item' => {'name' => 'chain shirt +1', 'bonus' => 1}}
            ]
          },
          {'slot' => 'potion_heal', 'chance' => 0.50, 'item' => {'name' => 'Potion of Lesser Healing'}},
          {'slot' => 'potion_invis', 'chance' => 0.01, 'item' => {'name' => 'Potion of Invisibility'}}
        ],
        'gold' => '5'
      }
    }
  end

  before do
    allow(Templates).to receive(:find).and_call_original
    allow(Templates).to receive(:find).with('slaver').and_return(slaver)
    allow(Templates).to receive(:gear_tables).and_return(tables)
  end

  describe '.adjust_score' do
    it 'replaces with an integer adjustment' do
      expect(Templates.adjust_score(10, 14)).to eq(14)
    end

    it 'adds a signed string adjustment' do
      expect(Templates.adjust_score(10, '+3')).to eq(13)
      expect(Templates.adjust_score(10, '-2')).to eq(8)
    end
  end

  describe '.apply_variant!' do
    it 'merges ability scores additively when given +N strings' do
      char = {'ability_scores' => {'cha' => 6, 'int' => 7}}
      variant = {'overrides' => {'ability_scores' => {'cha' => '+2', 'int' => '+2'}}}
      Templates.apply_variant!(char, variant)
      expect(char['ability_scores']).to eq({'cha' => 8, 'int' => 9})
    end

    it 'replaces simple fields wholesale' do
      char = {'race' => ['orc']}
      variant = {'overrides' => {'race' => ['human']}}
      Templates.apply_variant!(char, variant)
      expect(char['race']).to eq(['human'])
    end

    it 'appends class levels via classes_add' do
      char = {'classes' => [{'level' => 3, 'class' => 'fighter'}]}
      variant = {'classes_add' => [{'level' => 1, 'class' => 'barbarian'}]}
      Templates.apply_variant!(char, variant)
      expect(char['classes'].map { |c| c['class'] }).to eq(['fighter', 'barbarian'])
    end

    it 'applies name_suffix' do
      char = {'name' => 'Slaver'}
      Templates.apply_variant!(char, {'name_suffix' => ' (Barb)'})
      expect(char['name']).to eq('Slaver (Barb)')
    end
  end

  describe '.instantiate' do
    it 'produces the baseline character when no variant rolls succeed' do
      # rng returns 0.99 each call -> no variant triggers (both chances 0.10)
      rng = instance_double(Random, rand: 0.99)
      allow(rng).to receive(:rand).with(no_args).and_return(0.99)
      allow(rng).to receive(:rand).with(anything) { |n| n - 1 }

      result = Templates.instantiate('slaver', new_id: 42, rng: rng)
      expect(result['id']).to eq(42)
      expect(result['name']).to eq('Slaver')
      expect(result['race']).to eq(['orc'])
      expect(result['applied_variants']).to be_nil
      expect(result).not_to have_key('variants')
      expect(result).not_to have_key('gear')
    end

    it 'applies the human variant when its roll succeeds' do
      # First rand() is for human variant (0.10). Second is barbarian (0.10).
      call_count = 0
      rng = instance_double(Random)
      allow(rng).to receive(:rand) do |*args|
        call_count += 1
        if args.empty?
          [0.05, 0.99, 0.99, 0.99][call_count - 1] || 0.99
        else
          args.first - 1   # deterministic gold dice
        end
      end
      result = Templates.instantiate('slaver', new_id: 99, rng: rng)
      expect(result['race']).to eq(['human'])
      expect(result['name']).to eq('Slaver (Human)')
      expect(result['ability_scores']['cha']).to eq(8)
      expect(result['ability_scores']['int']).to eq(9)
      expect(result['applied_variants']).to include('human')
      expect(result['gold']).to eq(10) # variant gear_patch override
    end

    it 'stacks multiple variants when both succeed' do
      rng = instance_double(Random)
      call_count = 0
      allow(rng).to receive(:rand) do |*args|
        call_count += 1
        if args.empty?
          0.01 # every variant chance succeeds
        else
          0    # minimum die roll
        end
      end
      result = Templates.instantiate('slaver', new_id: 7, rng: rng)
      expect(result['applied_variants']).to include('human', 'barbarian')
      expect(result['classes'].map { |c| c['class'] }).to include('fighter', 'barbarian')
      expect(result['name']).to eq('Slaver (Human) (Barb)')
    end

    it 'raises on unknown template id' do
      allow(Templates).to receive(:find).with('nope').and_return(nil)
      expect { Templates.instantiate('nope', new_id: 1) }.to raise_error(ArgumentError)
    end
  end

  describe '.preview_character' do
    it 'strips variants and gear and assigns a synthetic id' do
      preview = Templates.preview_character(slaver)
      expect(preview).not_to have_key('variants')
      expect(preview).not_to have_key('gear')
      expect(preview['id']).to eq('template:slaver')
      expect(preview['group']).to eq('Enemies')
    end
  end
end

RSpec.describe GearTable do
  let(:tables) do
    {
      'pirate' => {
        'id' => 'pirate',
        'rolls' => [
          {'slot' => 'weapon', 'item' => {'name' => 'scimitar'}},
          {'slot' => 'armor', 'chance' => 0.50, 'item' => {'name' => 'leather'}}
        ],
        'gold' => '1d6 + 2'
      }
    }
  end

  describe '.resolve' do
    it 'returns the named table deep-copied' do
      result = GearTable.resolve('pirate', tables)
      expect(result['rolls'].first['item']['name']).to eq('scimitar')
      result['rolls'].first['item']['name'] = 'mutated'
      expect(tables['pirate']['rolls'].first['item']['name']).to eq('scimitar')
    end

    it 'returns an empty table for nil ref' do
      expect(GearTable.resolve(nil, tables)).to eq({'rolls' => [], 'gold' => nil})
    end

    it 'accepts inline tables' do
      inline = {'rolls' => [{'slot' => 'x', 'item' => {'name' => 'inline'}}]}
      expect(GearTable.resolve(inline, tables)['rolls'].first['item']['name']).to eq('inline')
    end
  end

  describe '.apply_patch' do
    it 'overrides gold' do
      table = {'rolls' => [], 'gold' => '1d6'}
      result = GearTable.apply_patch(table, {'gold' => '5d10'})
      expect(result['gold']).to eq('5d10')
    end

    it 'replaces a slot by id' do
      table = {
        'rolls' => [
          {'slot' => 'weapon', 'item' => {'name' => 'old'}},
          {'slot' => 'armor', 'item' => {'name' => 'leather'}}
        ]
      }
      result = GearTable.apply_patch(table, {'rolls' => {'weapon' => {'item' => {'name' => 'new'}}}})
      expect(result['rolls'].find { |r| r['slot'] == 'weapon' }['item']['name']).to eq('new')
      expect(result['rolls'].find { |r| r['slot'] == 'armor' }['item']['name']).to eq('leather')
    end

    it 'drops a slot with nil' do
      table = {
        'rolls' => [
          {'slot' => 'weapon', 'item' => {'name' => 'old'}},
          {'slot' => 'armor', 'item' => {'name' => 'leather'}}
        ]
      }
      result = GearTable.apply_patch(table, {'rolls' => {'weapon' => nil}})
      expect(result['rolls'].length).to eq(1)
      expect(result['rolls'].first['slot']).to eq('armor')
    end
  end

  describe '.roll_row' do
    it 'always returns guaranteed items' do
      row = {'slot' => 'w', 'item' => {'name' => 'x'}}
      expect(GearTable.roll_row(row, Random.new)['name']).to eq('x')
    end

    it 'returns nil when independent chance fails' do
      rng = instance_double(Random, rand: 0.99)
      row = {'slot' => 'p', 'chance' => 0.5, 'item' => {'name' => 'potion'}}
      expect(GearTable.roll_row(row, rng)).to be_nil
    end

    it 'returns item when independent chance succeeds' do
      rng = instance_double(Random, rand: 0.01)
      row = {'slot' => 'p', 'chance' => 0.5, 'item' => {'name' => 'potion'}}
      expect(GearTable.roll_row(row, rng)['name']).to eq('potion')
    end
  end

  describe '.roll_weighted' do
    let(:options) do
      [
        {'chance' => 0.90, 'item' => {'name' => 'light'}},
        {'chance' => 0.05, 'item' => {'name' => 'medium'}},
        {'chance' => 0.05, 'item' => {'name' => 'plus1', 'bonus' => 1}}
      ]
    end

    it 'picks the first option when rand is below its cumulative chance' do
      rng = instance_double(Random, rand: 0.50)
      result = GearTable.roll_weighted(options, rng)
      expect(result['name']).to eq('light')
    end

    it 'picks the second option when rand is in its window' do
      rng = instance_double(Random, rand: 0.93)
      result = GearTable.roll_weighted(options, rng)
      expect(result['name']).to eq('medium')
    end

    it 'picks the third option when rand lands in the tail' do
      rng = instance_double(Random, rand: 0.97)
      result = GearTable.roll_weighted(options, rng)
      expect(result['name']).to eq('plus1')
      expect(result['bonus']).to eq(1)
    end

    it 'returns nil when the sum is < 1.0 and rand falls in the remainder' do
      tail_options = [
        {'chance' => 0.40, 'item' => {'name' => 'a'}},
        {'chance' => 0.40, 'item' => {'name' => 'b'}}
      ]
      rng = instance_double(Random, rand: 0.95)
      expect(GearTable.roll_weighted(tail_options, rng)).to be_nil
    end
  end

  describe '.roll_gold' do
    it 'returns nil for empty or missing expressions' do
      expect(GearTable.roll_gold(nil, Random.new)).to be_nil
      expect(GearTable.roll_gold('', Random.new)).to be_nil
    end

    it 'evaluates NdM + constant formulas' do
      rng = instance_double(Random)
      allow(rng).to receive(:rand) { |n| 0 } # minimum: each die yields 1
      expect(GearTable.roll_gold('2d6 + 5', rng)).to eq(7)
    end

    it 'handles negative modifiers' do
      rng = instance_double(Random)
      allow(rng).to receive(:rand) { |n| n - 1 } # maximum: each die yields n
      expect(GearTable.roll_gold('1d6 - 1', rng)).to eq(5)
    end

    it 'handles plain integer strings' do
      rng = instance_double(Random)
      expect(GearTable.roll_gold('10', rng)).to eq(10)
    end
  end

  describe '.roll' do
    it 'returns items and gold' do
      table = {
        'rolls' => [
          {'slot' => 'w', 'item' => {'name' => 'sword'}},
          {'slot' => 'p', 'chance' => 0.0, 'item' => {'name' => 'never'}}
        ],
        'gold' => '3'
      }
      rng = Random.new(42)
      items, gold = GearTable.roll(table, rng: rng)
      expect(items.map { |i| i['name'] }).to eq(['sword'])
      expect(gold).to eq(3)
    end
  end
end
