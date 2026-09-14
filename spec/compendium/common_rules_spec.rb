require 'spec_helper'
require 'rack/test'
require 'tmpdir'
require_relative '../../app'

# The Common Rules: one Compendium page per concept folder under
# docs/common/. The DM sees the whole merged design document (player prose
# and implementer rules together) plus config and tests; a player sees only
# the @player passages of the concepts that carry an @chapter directive.
RSpec.describe 'Compendium Common Rules', type: :request do
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

  # A passage that exists only in the implementer half of the merged
  # dice_resolution design doc.
  IMPLEMENTER_ONLY = 'starting_contribution'.freeze
  # A passage that exists only in the player half.
  PLAYER_ONLY = 'you grab a handful of'.freeze

  describe 'discovery' do
    it 'derives a concept from every folder under docs/common/ with no registry' do
      keys = CommonDocs.concepts.map(&:key)
      expect(keys).to include('dice_resolution', 'conditions', 'equipment', 'atlas')
      expect(keys).not_to include('ui') # website design, not a shared rules concept
    end

    it 'orders the player manual by @chapter and reports duplicates' do
      expect(CommonDocs.chapters.map { |c| [c.chapter, c.chapter_title] })
        .to eq([[1, 'Magical Tier'], [2, 'Dice Resolution'],
                [3, 'Check Resolution'], [4, 'Conditions']])
      expect(CommonDocs.duplicate_chapters).to be_empty
    end

    it 'treats a concept with no @chapter as absent from the book' do
      expect(CommonDocs.find('equipment').chapter?).to be false
      expect(CommonDocs.chapters.map(&:key)).not_to include('equipment')
    end
  end

  describe 'the marked-up design document' do
    let(:md) do
      <<~MD
        @chapter 9 Demo

        # Demo — Design

        @player
        Player lead.

        @implementation
        Implementer lead.

        ## Shared heading

        @player
        Player body.

        @implementation
        Implementer body.

        ## Implementer-only heading

        Unmarked content defaults to implementer.
      MD
    end

    it 'gives a player only the @player passages' do
      blocks = CommonDocs.blocks_for(CommonDocs.parse_blocks(md), :player)
      text   = blocks.map(&:text).join
      expect(text).to include('Player lead.', 'Player body.')
      expect(text).not_to include('Implementer lead.', 'Implementer body.')
    end

    it 'treats unmarked content as implementer-only, so a forgotten marker never leaks' do
      blocks = CommonDocs.blocks_for(CommonDocs.parse_blocks(md), :player)
      expect(blocks.map(&:text).join).not_to include('Unmarked content defaults')
    end

    it 'drops a heading whose whole section is implementer-only' do
      headings = CommonDocs.blocks_for(CommonDocs.parse_blocks(md), :player)
                           .select { |b| b.kind == :heading }.map(&:text)
      expect(headings).to include('Shared heading')
      expect(headings).not_to include('Implementer-only heading')
    end

    it 'resets the mode at every heading so an open @player cannot leak into the next section' do
      leaky = "@player\nVisible.\n\n## Next section\n\nShould not be player content.\n"
      text  = CommonDocs.blocks_for(CommonDocs.parse_blocks(leaky), :player).map(&:text).join
      expect(text).to include('Visible.')
      expect(text).not_to include('Should not be player content.')
    end

    it 'ignores markers and headings inside a fenced block' do
      fenced = "@player\nBefore.\n\n```yaml\n# @implementation\n## Not a heading\n```\n"
      blocks = CommonDocs.parse_blocks(fenced)
      expect(blocks.select { |b| b.kind == :heading }).to be_empty
      expect(blocks.map(&:text).join).to include('## Not a heading')
    end

    it 'strips @chapter, @function and ```test from the rendered page' do
      src = "@chapter 9 Demo\n@function do_thing\n\n```test\nsecret case\n```\n\n@player\nBody.\n"
      out = CommonDocs.strip_directives(src)
      expect(out).not_to include('@function', 'secret case')
      expect(CommonDocs.parse_blocks(out).map(&:text).join).not_to include('@chapter')
    end
  end

  describe '{{Config Key}} substitution' do
    let(:values) { CommonDocs.substitution_values(CommonDocs.find('dice_resolution')) }

    it 'resolves a key from the concept\'s own config' do
      expect(CommonDocs.substitute('TN {{Base Target Number}}', values)).to eq('TN 8')
    end

    it 'falls back to another concept\'s config' do
      expect(CommonDocs.substitute('{{Round Length}}', values)).to eq('6')
    end

    it 'applies an integer offset so a worked example follows the value' do
      expect(CommonDocs.substitute('{{Base Target Number - 1}}', values)).to eq('7')
      expect(CommonDocs.substitute('{{Base Target Number + 2}}', values)).to eq('10')
    end

    it 'renders an unknown key loudly rather than dropping it' do
      expect(CommonDocs.substitute('{{Not A Key}}', values)).to include('doc-missing-key')
    end

    it 'leaves no unsubstituted token in any rendered chapter' do
      CommonDocs.chapters.each do |concept|
        html = CommonDocs.render_design(concept, audience: :player)
        expect(html).not_to include('{{'), "#{concept.key} has an unsubstituted token"
        expect(html).not_to include('doc-missing-key'), "#{concept.key} references an unknown config key"
      end
    end
  end

  describe 'config tables' do
    let(:yaml) do
      <<~YAML
        # File preamble, belongs to no key.

        # ---- A Section ----

        # Describes the pair below.
        Shown One: 1
        Shown Two: 2

        # @dm
        # Internal knob.
        Hidden Key: 3
      YAML
    end

    def parse_tmp(body)
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'demo_config.yaml')
        File.write(path, body)
        yield ConfigTables.parse(path)
      end
    end

    it 'reads the section divider, and applies a comment block to the run of keys under it' do
      parse_tmp(yaml) do |sections|
        expect(sections.map(&:title)).to eq(['A Section'])
        rows = sections.first.rows
        expect(rows.map(&:key)).to eq(['Shown One', 'Shown Two', 'Hidden Key'])
        expect(rows[0].description).to eq('Describes the pair below.')
        expect(rows[1].description).to eq('Describes the pair below.')
      end
    end

    it 'keeps a preamble separated by a blank line out of the first key\'s description' do
      parse_tmp(yaml) { |s| expect(s.first.rows.first.description).not_to include('File preamble') }
    end

    it 'defaults a config key to player-visible and hides only the @dm exceptions' do
      parse_tmp(yaml) do |sections|
        player = ConfigTables.render(sections, audience: :player)
        dm     = ConfigTables.render(sections, audience: :dm)
        expect(player).to include('Shown One', 'Shown Two')
        expect(player).not_to include('Hidden Key')
        expect(dm).to include('Hidden Key')
      end
    end
  end

  describe 'as the DM' do
    before { as_dm }

    it 'lists the Common Rules group with an entry per concept' do
      body = visit('/compendium').body
      expect(body).to include('Common Rules (DM)')
      expect(body).to include('?view=common:dice_resolution')
      expect(body).to include('?view=common:equipment')
    end

    it 'renders the whole merged document — player prose and implementer rules' do
      body = visit('/compendium?view=common:dice_resolution').body
      expect(body).to include(IMPLEMENTER_ONLY)
      expect(body).to include(PLAYER_ONLY)
    end

    it 'marks the player-facing passages so the merged document can be reviewed' do
      expect(visit('/compendium?view=common:dice_resolution').body).to include('doc-player')
    end

    it 'appends the config table and the canonical tests' do
      body = visit('/compendium?view=common:dice_resolution').body
      expect(body).to include('config-table')
      expect(body).to include('doc-tests')
    end

    it 'links a chapter concept to the player view of the same concept' do
      expect(visit('/compendium?view=common:dice_resolution').body)
        .to include('/compendium?view=dice_resolution')
    end

    it 'shows a coverage overview naming the files a concept is missing' do
      body = visit('/compendium?view=common').body
      expect(body).to include('Coverage')
      # magical_tier carries only a design doc.
      expect(body).to include('missing')
    end

    it 'renders a concept that has no design document as a visible gap' do
      concept = CommonDocs.find('magical_tier')
      expect(concept.tests?).to be false
      expect(visit('/compendium?view=common:magical_tier').status).to eq(200)
    end
  end

  describe 'as a player' do
    before { as_player }

    it 'never shows the DM-only groups' do
      body = visit('/compendium').body
      expect(body).not_to include('Common Rules (DM)')
      expect(body).not_to include('Website Design (DM)')
    end

    it 'lists the chapters in book order with their numbers' do
      body = visit('/compendium').body
      expect(body).to include('?view=magical_tier', '?view=dice_resolution',
                              '?view=check_resolution', '?view=conditions')
      expect(body.index('?view=dice_resolution')).to be < body.index('?view=check_resolution')
    end

    it 'renders a chapter with the player prose only' do
      body = visit('/compendium?view=dice_resolution').body
      expect(body).to include(PLAYER_ONLY)
      expect(body).not_to include(IMPLEMENTER_ONLY)
    end

    it 'titles the chapter from @chapter rather than the design doc H1' do
      body = visit('/compendium?view=dice_resolution').body
      expect(body).to include('>Dice Resolution</h1>')
      expect(body).not_to include('Dice and Resolution Mechanics')
    end

    it 'substitutes live config values into the chapter prose' do
      expect(visit('/compendium?view=dice_resolution').body).to include('Base TN is 8')
    end

    it 'shows the config table but never the tests' do
      body = visit('/compendium?view=dice_resolution').body
      expect(body).to include('config-table')
      expect(body).not_to include('doc-tests')
    end

    it 'bounces a DM-only concept key to the Glossary' do
      body = visit('/compendium?view=common:dice_resolution').body
      expect(body).to include('<h1>Glossary</h1>')
      expect(body).not_to include(IMPLEMENTER_ONLY)
    end

    it 'bounces the coverage overview to the Glossary' do
      expect(visit('/compendium?view=common').body).to include('<h1>Glossary</h1>')
    end

    it 'still resolves the pre-rename chapter links' do
      expect(visit('/compendium?view=dice').body).to include(PLAYER_ONLY)
      expect(visit('/compendium?view=checks').body).to include('sneaking past a guard')
    end
  end

  describe 'as the DM viewing as a player' do
    it 'hides the DM-only entries for the duration of the override' do
      as_dm
      allow_any_instance_of(Sinatra::Application).to receive(:viewing_as_player?).and_return(true)
      allow_any_instance_of(Sinatra::Application).to receive(:dm_view?).and_return(false)

      expect(visit('/compendium').body).not_to include('Common Rules (DM)')
      expect(visit('/compendium?view=common:dice_resolution').body).to include('<h1>Glossary</h1>')
    end
  end

  describe 'the Glossary' do
    it 'discovers every concept glossary rather than a hand-written list' do
      keys = GlossaryDocs.sources.map { |s| s[:key] }
      expect(keys.first).to eq('common')
      expect(keys).to include('equipment', 'atlas', 'creatures', 'timekeeping')
    end

    it 'skips a glossary file that defines no terms' do
      # check_resolution's glossary is an H1 and intro prose only.
      expect(GlossaryDocs.render_source(
        GlossaryDocs.sources.find { |s| s[:key] == 'check_resolution' }
      )).to eq('')
    end
  end
end
