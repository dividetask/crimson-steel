# Session Tests — shared setup. See docs/project/session_tests.md.
#
# Loading this file pulls in the app, the isolated test Campaign, the
# scripted-dice bridge, and the session DSL, and registers the `:session`
# shared context every scenario runs inside.

require 'spec_helper'
require 'rack/test'
require_relative '../../../app'
require_relative 'campaign'
require_relative 'dice_bridge'
require_relative 'transcript'
require_relative 'session'

module Sessions
  # Helpers available inside a `:session` example.
  module ExampleHelpers
    # The session under test. Named after the example, so each scenario
    # writes its own transcript under the scenario file's directory.
    def session
      @session ||= Sessions::Session.new(
        RSpec.current_example.full_description,
        group: RSpec.current_example.example_group.parent_groups.last.description
      )
    end

    # Marks behavior the Session Tests expect but the app does not do yet.
    # The expectation below it is written for real and left to fail: RSpec
    # reports it as pending, and shouts the day it starts passing.
    #
    #   gap 'a multi-day jump does not tick Afflictions'
    #   expect(session.afflictions('Garroth Vask')).to be_empty
    def gap(reason)
      pending("not yet implemented — #{reason}")
    end
  end
end

RSpec.shared_context 'a game session', :session do
  include Sessions::ExampleHelpers

  before do
    skip 'node is required to resolve scripted dice' unless Sessions::DiceBridge.available?
  end

  after do
    @session&.finish!
  end
end
