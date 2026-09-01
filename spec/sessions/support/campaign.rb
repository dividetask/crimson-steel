require 'fileutils'
require 'tmpdir'
require 'yaml'
require 'json'

module Sessions
  # An isolated Campaign for one Session Test.
  #
  # Every domain that persists state is pointed at a throwaway directory
  # seeded from `spec/sessions/fixtures/` — the live `data/` directory is
  # never read and never written. The rule data under `docs/common/`
  # (spells, afflictions, skills, shops, item catalog, calendar) is the
  # real thing: a Session Test asserts against the Campaign's own rules,
  # not against a second copy of them.
  #
  # Creature files are shadowed rather than merged. `Creatures::Dataset`
  # unions the writable overlay with the shipped `.example` files, so the
  # fixture directory gets an empty `characters: []` file for every
  # example basename it does not itself supply; without that, the example
  # party would walk into every scenario.
  #
  # See docs/project/session_tests.md — "The test Campaign".
  class Campaign
    FIXTURE_DIR = File.expand_path('../fixtures', __dir__).freeze
    CREATURE_EXAMPLE_DIR = File.expand_path(
      '../../../docs/common/creatures', __dir__
    ).freeze

    attr_reader :dir

    def self.install!
      new.tap(&:install!)
    end

    def initialize
      @dir = Dir.mktmpdir('session-campaign')
      @saved = {}
    end

    def path(name)
      File.join(@dir, name)
    end

    def install!
      seed_files!
      save_domain_state!
      point_domains_at_fixture!
      self
    end

    # Restore the process-wide domain singletons the app boots with, so a
    # Session Test leaves nothing behind for the specs that follow it.
    def uninstall!
      Creatures::Dataset.reset!
      Creatures.reset!
      Equipment.reset!
      Encounter.reset!
      Atlas.state = nil
      SceneRound.reset!
      RollLog.reset!
      Conditions.store = @saved[:conditions_store]
      Chronicle.store  = @saved[:chronicle_store]
      FileUtils.remove_entry(@dir) if File.directory?(@dir)
    end

    private

    def seed_files!
      Dir.glob(File.join(FIXTURE_DIR, '*')).each do |src|
        FileUtils.cp(src, File.join(@dir, File.basename(src)))
      end
      shadow_unused_creature_files!
    end

    # One empty overlay per shipped example roster the fixture does not
    # replace, so no example Creature loads.
    def shadow_unused_creature_files!
      Dir.glob(File.join(CREATURE_EXAMPLE_DIR, Creatures::Dataset::PATTERN)).each do |example|
        overlay = Creatures::Dataset.overlay_name(File.basename(example))
        target = File.join(@dir, overlay)
        next if File.exist?(target)
        File.write(target, "# Shadow file — keeps the shipped example roster out of Session Tests.\ncharacters: []\n")
      end
    end

    def save_domain_state!
      @saved[:conditions_store] = Conditions.store
      @saved[:chronicle_store]  = Chronicle.store
    end

    def point_domains_at_fixture!
      Creatures.reset!
      Creatures::Dataset.data_dir = @dir

      Conditions.store = Conditions::Store.new({}, data_path: path('conditions_data.json'))

      Chronicle.store = Chronicle::Store.load(
        data_path: path('chronicle_data.json'),
        example_path: path('chronicle_data.json')
      )

      Atlas.state = Atlas::State.load(
        data_path: path('atlas_data.json'),
        example_path: path('atlas_data.json')
      )

      Equipment.reset!
      dataset = Equipment::Dataset.load(
        data_path: path('equipment_data.yaml'),
        example_path: path('equipment_data.yaml')
      )
      shop_catalog = Equipment::ShopCatalog.load
      Equipment.instance_variable_set(:@instance, Equipment::Instance.new(
        catalog: Equipment.catalog,
        store: Equipment::Dataset::StoreAdapter.new(dataset),
        creature_accessor: Equipment::Dataset::CreatureAdapter.new(dataset),
        loot: Equipment::LootTables.load,
        generic_shops: shop_catalog.generic_shops,
        game_day: shop_catalog.current_day
      ))

      SceneRound.instance_variable_set(
        :@store, SceneRound::Store.load(data_path: path('scene_round.json'))
      )
      RollLog.instance_variable_set(
        :@store, RollLog::Store.load(data_path: path('roll_log.json'))
      )

      Encounter.reset!
      Encounter.state = Encounter::State.new(
        {}, data_path: path('encounter_data.json'),
        creature_lookup: ->(id) { Creatures.lookup(id) },
        conditions_for: ->(id) { Conditions.store.instance_for(id) }
      )
    end
  end
end
