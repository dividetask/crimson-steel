require 'spec_helper'
require 'rack/test'
require_relative '../../app'

# The Compendium surfaces the DM-only "website design" reference pages
# (DesignDocs) as extra left-nav entries. Players never see them, and a
# player who requests one of their ?view= keys is bounced to the Glossary.
RSpec.describe 'Compendium DM-only design docs', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  def as_dm
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(true)
  end

  def as_player
    allow_any_instance_of(Sinatra::Application).to receive(:dm_host?).and_return(false)
  end

  def visit(path)
    header 'Host', 'localhost'
    get path, {}, 'REMOTE_ADDR' => '127.0.0.1'
    last_response
  end

  describe 'as the DM' do
    before { as_dm }

    it 'lists the DM-only Website Design group with each entry' do
      body = visit('/compendium').body
      expect(body).to include('Website Design (DM)')
      expect(body).to include('?view=combat"')
      expect(body).to include('?view=action_builder')
      expect(body).to include('?view=combat_interfaces')
      expect(body).to include('?view=combat_test_data')
    end

    it 'renders the combat encounter stub (the turn), which builds the blob for the Action Builder' do
      body = visit('/compendium?view=combat').body
      expect(body).to include('Combat Encounter Stub')
      expect(body).to include('The turn')
      expect(body).to include('/compendium?view=action_builder')
      # Combat's host builds the blob via the *_builder_blob helpers.
      expect(body).to include('attack_builder_blob')
    end

    it 'renders the Action Builder contract as-built (rolls / steps / patch)' do
      body = visit('/compendium?view=action_builder').body
      expect(body).to include('Action Builder')
      expect(body).to include('action:confirmed')
      # It documents the real blob the code consumes.
      expect(body).to include('actionBuilder.js')
      expect(body).to include('patch')
    end

    it 'documents a worked example of the real blob in the test-data page' do
      body = visit('/compendium?view=combat_test_data').body
      expect(body).to include('rolls')
      expect(body).to include('steps')
      expect(body).to include('builder_blob')
    end

    it 'strips developer directives and test blocks from the rendered page' do
      body = visit('/compendium?view=combat').body
      expect(body).not_to include('@function')
      # A unique string that lives only inside the hidden ```test block.
      expect(body).not_to include('assert Combat Pool never goes negative')
    end

    it 'renders the required-interfaces and test-data pages' do
      expect(visit('/compendium?view=combat_interfaces').body).to include('Required Interfaces')
      expect(visit('/compendium?view=combat_test_data').body).to include('Test Data')
    end
  end

  describe 'as a player' do
    before { as_player }

    it 'never shows the DM-only nav group' do
      expect(visit('/compendium').body).not_to include('Website Design (DM)')
    end

    it 'bounces a DM-only ?view= key to the default Glossary' do
      body = visit('/compendium?view=combat').body
      expect(body).to include('<h1>Glossary</h1>')
      expect(body).not_to include('Combat Encounter Stub')
    end
  end

  describe 'as the DM viewing as a player' do
    it 'hides the DM-only entries for the duration of the override' do
      as_dm
      allow_any_instance_of(Sinatra::Application)
        .to receive(:viewing_as_player?).and_return(true)
      allow_any_instance_of(Sinatra::Application)
        .to receive(:dm_view?).and_return(false)

      expect(visit('/compendium').body).not_to include('Website Design (DM)')
      expect(visit('/compendium?view=combat').body).to include('<h1>Glossary</h1>')
    end
  end
end
