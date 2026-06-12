require 'spec_helper'
require 'tmpdir'
require_relative '../../app'

# A Spell cast from an item (a consumable, or a Wand / Ring grant) may be rolled
# with any skill the Spell lists plus Evocation (the universal item-form skill).
# And every Spell castable from an item is offered under the Item pane — the
# Wand / Ring grants additionally still appear under Cast.
RSpec.describe 'Item-cast skills and pane listing', type: :request do
  let(:helpers) { Sinatra::Application.new! }

  describe '#item_skill_options' do
    it 'offers every listed skill plus Evocation' do
      v = Abilities.lookup('Spark Shower')
      expect(helpers.send(:item_skill_options, v)).to eq(%w[nature arcana evocation])
    end

    it 'resolves a Set-Skill family to the actor’s trained instance, else drops it' do
      v = Abilities.lookup('Heal') # skills: healing, nature, perform_ (+ evocation)
      bard = double(trained_skills: ['perform_dance'])
      plain = double(trained_skills: [])
      expect(helpers.send(:item_skill_options, v, bard)).to eq(%w[healing nature perform_dance evocation])
      expect(helpers.send(:item_skill_options, v, plain)).to eq(%w[healing nature evocation])
    end
  end

  describe 'Wand / Ring grants under both Item and Cast' do
    let(:tmp) { Dir.mktmpdir('item-cast') }
    let(:acc) do
      a = Object.new
      { max_mana: 12, tier: 2, id: 'r1', name: 'Wielder', tags: [], granted_abilities: [],
        trained_skills: [], record: {} }.each { |m, val| a.define_singleton_method(m) { val } }
      a.define_singleton_method(:ranks_for) { |_k| 0 }
      a.define_singleton_method(:attribute_value) { |_x| 12 }
      a
    end

    before do
      File.write(File.join(tmp, 'equipment_data.yaml'), <<~YAML)
        characters:
          r1:
            inventory:
            - item: Ring of Shooting Stars
              tier: 2
              equipped: true
      YAML
      ds = Equipment::Dataset.load(data_path: File.join(tmp, 'equipment_data.yaml'))
      Equipment.instance_variable_set(:@instance, Equipment::Instance.new(
        catalog: Equipment.catalog,
        store: Equipment::Dataset::StoreAdapter.new(ds),
        creature_accessor: Equipment::Dataset::CreatureAdapter.new(ds),
        loot: Equipment::LootTables.load))
      allow(Creatures).to receive(:lookup) { |id| id.to_s == 'r1' ? acc : nil }
      Encounter.state = Encounter::State.new(
        {}, data_path: File.join(tmp, 'enc.json'),
        creature_lookup: ->(id) { id.to_s == 'r1' ? acc : nil },
        conditions_for: ->(_id) { nil },
        current_timestamp_fn: -> { { day_index: 0, round_of_day: 0 } },
        rounds_per_day: 1000)
      @cid = Encounter.state.add_combatant('r1')
    end
    after do
      Equipment.reset!
      FileUtils.remove_entry(tmp) if File.exist?(tmp)
    end

    def spell_names(blob)
      blob[:steps].find { |s| s[:key] == 'spell' }[:options]
                  .select { |o| o[:value] }.map { |o| o[:summary] || o[:label] }
    end

    it 'lists the Ring’s Spells in the Item pane' do
      expect(spell_names(helpers.send(:item_builder_blob, @cid)))
        .to include('Spark Shower', 'Shooting Stars')
    end

    it 'still lists the Ring’s Spells in the Cast pane' do
      expect(spell_names(helpers.send(:cast_builder_blob, @cid)))
        .to include('Spark Shower', 'Shooting Stars')
    end

    it 'offers all listed skills plus Evocation on a granted Spell' do
      granted = helpers.send(:granted_item_castables, @cid, acc, 10, 12)
      spark = granted.find { |g| g[:name] == 'Spark Shower' }
      expect(spark[:skill_options].map { |s| s[:skill] }).to eq(%w[nature arcana evocation])
    end
  end
end
