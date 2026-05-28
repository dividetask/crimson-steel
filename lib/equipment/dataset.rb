require 'yaml'
require 'fileutils'

module Equipment
  # Persistence-backed owner store for the running app. Holds the
  # Character, Party, and Ground Pile Inventories from the equipment
  # data file in memory and writes every mutation back to disk.
  #
  # Load order mirrors the other domains: `data/equipment_data.yaml`
  # when present, otherwise the read-only
  # `docs/common/equipment/equipment_data.example.yaml`. Mutations are
  # always written to the data path.
  #
  # Two thin adapters expose the Dataset under the interfaces the
  # Instance expects: StoreAdapter (non-Creature Owners) and
  # CreatureAdapter (Character Inventories via the Creature accessor
  # contract).
  class Dataset
    DATA_PATH    = File.expand_path('../../data/equipment_data.yaml', __dir__)
    EXAMPLE_PATH = File.expand_path('../../docs/common/equipment/equipment_data.example.yaml', __dir__)

    attr_reader :owners, :data_path

    def initialize(owners = {}, data_path: DATA_PATH)
      @owners = owners
      @data_path = data_path
    end

    def self.load(data_path: DATA_PATH, example_path: EXAMPLE_PATH)
      path = File.exist?(data_path) ? data_path : example_path
      raw = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      owners = {}

      (raw['characters'] || {}).each do |id, body|
        owners["character:#{id}"] = stacks_of(body)
      end
      owners['party'] = stacks_of(raw['party']) if raw['party']
      (raw['ground_piles'] || []).each do |pile|
        owners["ground:#{pile['location']}"] = stacks_of(pile)
      end

      new(owners, data_path: data_path)
    end

    def self.stacks_of(body)
      Array(body && body['inventory']).map { |s| Stack.normalize(s) }
    end

    def exists?(owner_id)      ; @owners.key?(owner_id)      ; end
    def inventory(owner_id)    ; @owners[owner_id]           ; end

    def set(owner_id, stacks)
      @owners[owner_id] = stacks
      persist!
      stacks
    end

    def delete(owner_id)
      @owners.delete(owner_id)
      persist!
    end

    # Serializes Character / Party / Ground Pile Owners back to the data
    # file. Shop Owners (kept in shops.yaml) are not written here.
    def persist!
      characters = {}
      party = nil
      piles = []

      @owners.each do |owner_id, stacks|
        next if stacks.nil?
        body = { 'inventory' => stacks.map(&:to_h) }
        case owner_id
        when /\Acharacter:(.+)\z/
          key = ::Regexp.last_match(1)
          characters[key.match?(/\A\d+\z/) ? key.to_i : key] = body
        when 'party'
          party = body
        when /\Aground:(.+)\z/
          piles << body.merge('location' => ::Regexp.last_match(1))
        end
      end

      out = {}
      out['characters']   = characters unless characters.empty?
      out['party']        = party if party
      out['ground_piles'] = piles unless piles.empty?

      FileUtils.mkdir_p(File.dirname(@data_path))
      tmp = "#{@data_path}.tmp"
      File.write(tmp, YAML.dump(out))
      File.rename(tmp, @data_path)
    end

    # Store interface for non-Creature Owners (Party, Ground Piles,
    # Shops). Shops live only in memory until shop persistence lands.
    class StoreAdapter
      def initialize(dataset) ; @dataset = dataset ; end
      def exists?(owner_id)   ; @dataset.exists?(owner_id)   ; end
      def inventory(owner_id) ; @dataset.inventory(owner_id) ; end
      def delete(owner_id)    ; @dataset.delete(owner_id)    ; end
      def ids                 ; @dataset.owners.keys         ; end

      def set_inventory(owner_id, stacks, _source_file = nil)
        @dataset.set(owner_id, stacks)
      end
    end

    # Creature accessor contract: keys Character Inventories by the bare
    # Creature id, mapping onto the `character:<id>` Owner.
    class CreatureAdapter
      def initialize(dataset) ; @dataset = dataset ; end
      def get_inventory(id)         ; @dataset.inventory("character:#{id}") || [] ; end
      def set_inventory(id, stacks) ; @dataset.set("character:#{id}", stacks)     ; end
      def source_file_for(_id)      ; @dataset.data_path                          ; end
      def exists?(id)               ; @dataset.exists?("character:#{id}")         ; end
    end
  end
end
