require 'dice_resolution'
require 'test_docs'

RSpec.describe TestDocs do
  describe '.render_for' do
    it 'renders the Encounter test file as test-card HTML for the encounter sub-view' do
      html = described_class.render_for('encounter')
      expect(html).to be_a(String)
      expect(html).to include('test-section')
      expect(html).to include('test-card')
      # A title lifted from docs/common/encounter/encounter_tests.md.
      expect(html).to include('Start Combat')
    end

    it 'titles the encounter sub-view' do
      expect(described_class.title_for('encounter')).to eq('Encounter — Tests')
    end

    it 'disables TN Success coloring for the encounter file' do
      # The config array `[1, 2, 4]` (Turns Per Round) would otherwise
      # be mis-colored as dice Successes; with TN coloring off no die
      # carries the .success class for this file.
      html = described_class.render_for('encounter')
      expect(html).not_to include('die success')
    end
  end
end
