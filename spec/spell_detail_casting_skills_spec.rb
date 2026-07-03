require 'spec_helper'
require 'rack/test'
require_relative '../app'

# GET /spell-detail renders a Spell's reference popup. No Skill actually carries
# Evocation as a Casting Skill — it is the innate / item-granted path (scrolls,
# potions, wands, some classes) — yet the Abilities resolver appends it to every
# Spell's `skills` at lookup time. The popup must never list it, while still
# showing the Spell's real Casting Skills.
RSpec.describe 'GET /spell-detail — Casting Skills', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  # Satisfy rack-protection's Host authorization (the default test host is
  # example.org, which is rejected).
  before { header 'Host', 'localhost' }

  def casting_skills_line(body)
    line = body.each_line.find { |l| l.include?('Casting Skills') } or return nil
    line.gsub(/<[^>]+>/, '').sub(/.*Casting Skills:\s*/, '').strip
  end

  it 'never lists Evocation as a Casting Skill' do
    %w[Heal\ Petty\ Wounds Fire\ Dart Vicious\ Mockery Spark\ Shower].each do |name|
      get "/spell-detail?name=#{Rack::Utils.escape(name)}"
      expect(last_response.status).to eq(200)
      expect(last_response.body).not_to include('Evocation')
    end
  end

  it 'still shows the Spell\'s real Casting Skills' do
    get "/spell-detail?name=#{Rack::Utils.escape('Fire Dart')}"
    # Fire Dart's data skills are [arcana]; only Evocation (universal) is dropped.
    expect(casting_skills_line(last_response.body)).to eq('Arcana')

    get "/spell-detail?name=#{Rack::Utils.escape('Heal Petty Wounds')}"
    line = casting_skills_line(last_response.body)
    expect(line).to include('Healing')
    expect(line).not_to match(/evocation/i)
  end
end
