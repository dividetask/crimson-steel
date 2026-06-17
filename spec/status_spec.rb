RSpec.describe 'Status — combat encounter stub demo' do
  it 'renders the turn-action stub and embeds the sample blob for the DM' do
    get '/status'
    expect(last_response).to be_ok
    expect(last_response.body).to include('class="turn-action"')
    expect(last_response.body).to include('id="combat-blob"')
    expect(last_response.body).to include('Ash Windmere')   # from the sample blob
    expect(last_response.body).to include('/combat.js')
  end

  it 'is DM-only — a player (non-loopback) gets the Not Yet Implemented notice' do
    get '/status', {}, { 'REMOTE_ADDR' => '192.168.1.50' }
    expect(last_response.status).to eq(404)
    expect(last_response.body).to include('Not Yet Implemented')
  end

  it 'sources its data only from the sample blob, never the data/ directory' do
    blob = Combat::SampleTurn.blob
    expect(blob[:combatant][:name]).to eq('Ash Windmere')
    expect(blob[:spells].map { |s| s[:name] }).to include('Fireball')
  end
end
