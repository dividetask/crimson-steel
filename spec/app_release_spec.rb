require 'spec_helper'
require 'rack/test'
require 'json'
require_relative '../app'

# Settings → App updates (lib/app_release.rb, docs/project/app_updates.md).
RSpec.describe 'App updates from the server', type: :request do
  include Rack::Test::Methods
  def app = Sinatra::Application

  before { header 'Host', '192.168.1.10:4567' }

  it 'parses versions the way the app names them' do
    expect(AppRelease.parse('v0.036 a (cb86)')).to eq([0, 36])
    expect(AppRelease.parse('v0.100.apk')).to eq([0, 100])
  end

  it 'offers the newest APK in android/versions to any device' do
    get '/api/app/latest', {}, 'REMOTE_ADDR' => '192.168.1.50'
    j = JSON.parse(last_response.body)
    newest = Dir.children(AppRelease::DIR).grep(AppRelease::NAME).max_by { |f| AppRelease.parse(f) }
    expect(j['version']).to eq(newest.delete_suffix('.apk'))
    get j['url'], {}, 'REMOTE_ADDR' => '192.168.1.50'
    expect(last_response.status).to eq(200)
    expect(last_response.content_type).to include('application/vnd.android.package-archive')
    expect(last_response.body.bytesize).to eq(j['size'])
  end
end
