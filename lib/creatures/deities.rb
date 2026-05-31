require 'yaml'

module Creatures
  # Deities catalog. Maps a (deity, domain) pair to the per-domain
  # extra spells a Cleric Creature with that pick gains, on top of
  # the Cleric Class's class-level `granted_spells`.
  module Deities
    DEFAULT_PATH = File.expand_path(
      '../../docs/common/creatures/deities.yaml', __dir__
    )

    module_function

    def data
      @data ||= YAML.safe_load_file(DEFAULT_PATH) || {}
    end

    def deities
      data['Deities'] || {}
    end

    # Domain catalog: domain name -> definition string.
    def domains
      data['Domains'] || {}
    end

    def domain_spells(deity_name, domain_name)
      d = deities[deity_name.to_s]
      return [] unless d
      (d['domain_spells'] || {}).fetch(domain_name.to_s, [])
    end

    def reset!
      @data = nil
    end
  end
end
