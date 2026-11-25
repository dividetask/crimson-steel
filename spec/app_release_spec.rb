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

  it 'warns at startup while the app code is newer than the newest APK' do
    allow(AppRelease).to receive(:latest).and_return(version: 'v0.036', path: '/x', size: 1)
    allow(AppRelease).to receive(:checkout_version).and_return('v0.037 b')
    expect(AppRelease.pending_warning).to include('v0.037 b', 'newest APK here is v0.036', 'git pull')
    allow(AppRelease).to receive(:checkout_version).and_return('v0.036 c')
    expect(AppRelease.pending_warning).to be_nil
  end

  it 'tells the app which commit the newest APK was built from, in /api/hello too' do
    get '/api/app/latest', {}, 'REMOTE_ADDR' => '192.168.1.50'
    j = JSON.parse(last_response.body)
    msg = `git -C #{File.dirname(AppRelease::DIR)} log -1 --format=%s -- #{File.join(AppRelease::DIR, j['version'] + '.apk')}`
    expect(j['commit']).to eq(msg[/\(from ([0-9a-f]+)\)/, 1])
    get '/api/hello', {}, 'REMOTE_ADDR' => '192.168.1.50'
    expect(JSON.parse(last_response.body)['app']).to eq('version' => j['version'], 'commit' => j['commit'])
  end

  it 'reads the version the checkout builds as' do
    expect(AppRelease.checkout_version).to match(/\Av\d+\.\d+ [a-z]+\z/)
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
