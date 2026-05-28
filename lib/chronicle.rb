require 'json'

# Chronicle domain. See docs/common/chronicle/chronicle_design.md.
#
# Holds the Campaign's mutable state — name, current Timestamp,
# Current Chapter, Chapter list and Entry collection. Loaded from
# `data/chronicle_data.json`, falling back to the example file in
# `docs/common/chronicle/` when the data file is absent. Mutations
# are persisted on every call.
module Chronicle
  module_function

  def store
    @store ||= Store.load
  end

  # Test seam — swap the live store. Pass nil to reset.
  def store=(s)
    @store = s
  end
end

require 'timekeeping'

require_relative 'chronicle/store'
require_relative 'chronicle/entry'
