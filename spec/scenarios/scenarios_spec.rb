require 'spec_helper'
require 'open3'
require 'rbconfig'

# The scenarios in test/scenarios/ on the fast track (DM clicks replaced by
# their routes). Each runs in its own process so it gets its own data folder.
RSpec.describe 'Scenarios (fast track)' do
  runner = File.expand_path('../../test/scenarios/run.rb', __dir__)
  names = Dir[File.expand_path('../../test/scenarios/*.rb', __dir__)].reject { _1.end_with?('/run.rb') }
                                                                       .map { File.basename(_1, '.rb') }

  names.each do |name|
    it name do
      out, status = Open3.capture2e(RbConfig.ruby, runner, '--fast', name)
      expect(status.success?).to be(true), out
    end
  end
end
