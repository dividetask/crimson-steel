require 'spec_helper'
require 'socket'
require 'json'
require 'lan_discovery'

RSpec.describe LanDiscovery do
  describe '.reply_for' do
    it 'answers a probe with the service, HTTP port and name' do
      reply = JSON.parse(described_class.reply_for('CRIMSON_STEEL_DISCOVER 1', http_port: 4567, name: 'Saltmere'))
      expect(reply).to eq('service' => 'crimson-steel', 'version' => 1, 'http_port' => 4567, 'name' => 'Saltmere')
    end

    it 'ignores anything that is not a probe' do
      expect(described_class.reply_for('hello', http_port: 4567)).to be_nil
      expect(described_class.reply_for('', http_port: 4567)).to be_nil
    end
  end

  describe '.start' do
    it 'replies to a UDP probe sent to its port' do
      port = 47_900 + rand(90)
      thread = described_class.start(http_port: 4567, name: -> { 'Test Campaign' }, port: port, logger: nil)
      expect(thread).not_to be_nil

      client = UDPSocket.new
      client.send('CRIMSON_STEEL_DISCOVER 1', 0, '127.0.0.1', port)
      ready = IO.select([client], nil, nil, 2)
      expect(ready).not_to be_nil
      data, = client.recvfrom(512)
      expect(JSON.parse(data)).to include('http_port' => 4567, 'name' => 'Test Campaign')
    ensure
      client&.close
      thread&.kill
    end
  end
end
