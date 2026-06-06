require 'yaml'

module Creatures
  # Deities and Domains catalog.
  #
  # `Domains` maps a domain name to its bonus `spells` (granted to any
  # Cleric who picks the domain) and its 1st-level `channel_divinity`
  # Talent (granted only when the domain is one of the Cleric's own
  # deity's domains). `Deities` maps a deity to its favored `domains`,
  # its `anathema` domains, and its 4th-level `channel_divinity` Talent.
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

    def domains
      data['Domains'] || {}
    end

    # Bonus spells granted by a domain, regardless of deity.
    def domain_spells(domain_name)
      (domains[domain_name.to_s] || {})['spells'] || []
    end

    # The domain's 1st-level Channel Divinity Talent name, or nil.
    def domain_channel_divinity(domain_name)
      (domains[domain_name.to_s] || {})['channel_divinity']
    end

    # The deity's favored domains.
    def deity_domains(deity_name)
      (deities[deity_name.to_s] || {})['domains'] || []
    end

    # The deity's 4th-level Channel Divinity Talent name, or nil.
    def deity_channel_divinity(deity_name)
      (deities[deity_name.to_s] || {})['channel_divinity']
    end

    def reset!
      @data = nil
    end
  end
end
