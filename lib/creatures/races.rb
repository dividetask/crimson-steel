require 'yaml'

module Creatures
  # Race catalog from `creatures_race.yaml`. Each entry may declare
  # a `parent` reference; `look_up` walks the chain root → leaf and
  # produces a single resolved Race with the chain rules applied:
  # `size` and `speed` first-in-chain wins, `attribute_adjustments`
  # accumulate per-attribute, `abilities` concatenate with
  # child-wins dedup on name.
  module Races
    DEFAULT_PATH = File.expand_path(
      '../../docs/common/creatures/creatures_race.yaml', __dir__
    )

    module_function

    def data
      @data ||= YAML.safe_load_file(DEFAULT_PATH) || {}
    end

    def known?(race_key)
      data.key?(race_key.to_s)
    end

    # Resolved Race entry: { race_key:, size:, speed:,
    # attribute_adjustments: { str: int, ... }, abilities: [{name:, min_level:}] }
    # Returns nil when race_key doesn't exist.
    def look_up(race_key)
      key = race_key.to_s
      return nil unless data.key?(key)

      chain = walk_chain(key)
      first_non_null = lambda do |field|
        # chain order is leaf → root: leaf wins.
        chain.each { |e| return e[field] if e[field] }
        nil
      end

      attr_adj = accumulate_adjustments(chain)
      abilities = accumulate_abilities(chain)

      {
        race_key: key,
        size: first_non_null.call('size'),
        speed: first_non_null.call('speed'),
        attribute_adjustments: attr_adj,
        abilities: abilities
      }
    end

    # Pretty chain string for headers, e.g. "Humanoid -> Dwarf -> Hill Dwarf".
    def chain_summary(race_key)
      walk_chain_keys(race_key.to_s).reverse
                                    .map { |k| k.split('_').map(&:capitalize).join(' ') }
                                    .join(' → ')
    end

    # Returns the chain leaf → root as a list of {key, entry} pairs.
    def walk_chain(start_key)
      chain = []
      seen = {}
      key = start_key
      while key
        raise "Race chain cycle at #{key.inspect}" if seen[key]
        seen[key] = true
        entry = data[key]
        raise "Race #{key.inspect} not found" unless entry
        chain << entry.merge('__key' => key)
        key = entry['parent']
      end
      chain
    end

    def walk_chain_keys(start_key)
      walk_chain(start_key).map { |e| e['__key'] }
    end

    def accumulate_adjustments(chain)
      attrs = Creatures::Config.attribute_keys
      acc = attrs.each_with_object({}) { |a, h| h[a] = 0 }

      chain.each do |entry|
        adj = entry['attribute_adjustments'] || entry['racial_adjustment']
        next unless adj
        if adj.key?('all')
          per_attr_keys = adj.keys - ['all']
          if per_attr_keys.any?
            raise "Race #{entry['__key'].inspect}: `all` is mutually exclusive " \
                  "with per-attribute adjustments"
          end
          attrs.each { |a| acc[a] += Integer(adj['all']) }
        else
          adj.each do |a, v|
            sym = a.to_sym
            raise "Race #{entry['__key'].inspect}: unknown attribute #{a.inspect}" \
              unless attrs.include?(sym)
            acc[sym] += Integer(v)
          end
        end
      end
      acc
    end

    # Concatenate abilities root → leaf with child-wins dedup on
    # `name`. Context entries (`{min_level: N}` with no name) act as
    # a rolling default for following entries within the same Race
    # entry's `abilities` list and are flattened away here.
    def accumulate_abilities(chain)
      acc = []
      seen = {}
      chain.reverse.each do |entry|
        flattened = flatten_context(entry['abilities'] || [])
        flattened.each do |ab|
          if seen[ab[:name]]
            # Child wins: replace in place at original position
            idx = acc.index { |x| x[:name] == ab[:name] }
            acc[idx] = ab if idx
          else
            acc << ab
            seen[ab[:name]] = true
          end
        end
      end
      acc
    end

    def flatten_context(list)
      rolling = 0
      out = []
      list.each do |entry|
        if entry.is_a?(Hash) && !entry['name'] && entry.key?('min_level')
          rolling = Integer(entry['min_level'])
        else
          name = entry.is_a?(Hash) ? entry['name'] : entry
          min_level = entry.is_a?(Hash) && entry.key?('min_level') \
                      ? Integer(entry['min_level']) : rolling
          out << { name: name, min_level: min_level }
        end
      end
      out
    end

    def reset!
      @data = nil
    end
  end
end
