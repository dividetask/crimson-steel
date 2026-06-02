require 'abilities'

# Helpers for the Abilities specs. Most specs drive the real loaded
# Catalog (the actual spells.yaml / talents.yaml shipped in
# docs/common/abilities) through the module entry points. Validation and
# edge-case specs build a small in-memory Catalog from inline entries so
# they don't depend on the contents of the data files.
module AbilitiesSpecHelpers
  # Build a Resolver over an inline catalog of Catalog Abilities, using
  # the real config (so range / activation / skill vocab resolves).
  # `config` is positional so an inline `'Name' => {...}` entries hash is
  # never mistaken for keyword arguments.
  def build_ability_resolver(entries, config = Abilities::Config.load)
    Abilities::Resolver.new(build_ability_catalog(entries, config))
  end

  # Build a Catalog (unvalidated until #validate!) from inline entries.
  def build_ability_catalog(entries, config = Abilities::Config.load)
    Abilities::Catalog.new(config: config, catalog: entries)
  end
end

RSpec.configure do |c|
  c.include AbilitiesSpecHelpers
end
