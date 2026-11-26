require 'spec_helper'
require 'yaml'
require_relative '../../lib/common_docs'

# `>` paths and {{table: …}}: printing rule data that lives inside a nested
# config value or in a catalog. See docs/common/file_conventions.md.
RSpec.describe 'Compendium catalog paths and tables' do
  let(:creatures) { CommonDocs.find('creatures') }
  let(:values)    { CommonDocs.substitution_values(creatures) }

  def sub(text) = CommonDocs.substitute(text, values, concept: creatures)

  def catalog(concept, file)
    YAML.safe_load_file(File.join(CommonDocs::ROOT, concept, file), aliases: true)
  end

  describe 'a path' do
    it 'reaches into a nested config value' do
      expected = values['Flatfooted Bonus']['type']
      expect(sub('{{Flatfooted Bonus > type}}')).to eq(expected)
    end

    it 'indexes a list by position' do
      expect(sub('{{Turns Per Round > 0}}')).to eq(values['Turns Per Round'][0].to_s)
    end

    it 'reaches a catalog in the concept folder by file name' do
      expected = catalog('creatures', 'character_creation.yaml')['Attribute Allocation']['point_buy']
      expect(sub('{{character_creation.yaml > Attribute Allocation > point_buy}}')).to eq(expected.to_s)
    end

    it 'finds a catalog that lives in another concept folder' do
      expected = catalog('proficiencies', 'skills.yaml')['Skills']['athletics']['attribute']
      expect(sub('{{skills.yaml > Skills > athletics > attribute}}')).to eq(expected)
    end

    it 'follows an integer key' do
      expected = catalog('creatures', 'character_creation.yaml')['Attribute Allocation']['cost'][10]
      expect(sub('{{character_creation.yaml > Attribute Allocation > cost > 10}}')).to eq(expected.to_s)
    end

    it 'takes an integer offset' do
      expected = catalog('creatures', 'character_creation.yaml')['Attribute Allocation']['point_buy']
      expect(sub('{{character_creation.yaml > Attribute Allocation > point_buy + 1}}')).to eq((expected + 1).to_s)
    end

    it 'prints a list inline and a map as its pairs' do
      expect(sub('{{Turns Per Round}}')).to eq(values['Turns Per Round'].join(', '))
      expect(sub('{{Flatfooted Bonus}}')).to eq(values['Flatfooted Bonus'].map { |k, v| "#{k}: #{v}" }.join(', '))
    end

    it 'renders a path that names nothing loudly' do
      expect(sub('{{Flatfooted Bonus > nope}}')).to include('doc-missing-key')
      expect(sub('{{no_such_catalog.yaml > Key}}')).to include('doc-missing-key')
    end

    it 'never reads a file outside the concept folders' do
      expect(sub('{{../../Gemfile.yaml}}')).to include('doc-missing-key')
      expect(sub('{{/etc/hostname.yaml}}')).to include('doc-missing-key')
    end
  end

  describe 'CatalogTables.render' do
    let(:beasts) do
      {
        'beast'     => { 'size' => 'medium', 'speed' => 30, 'adjust' => { 'int' => -8 }, 'traits' => [{ 'name' => 'scent' }] },
        'big_beast' => { 'parent' => 'beast', 'size' => 'large', 'adjust' => { 'str' => 4, 'int' => 1 }, 'traits' => [{ 'name' => 'hide' }] }
      }
    end

    def cells(html) = html.scan(%r{<t[hd](?:\s[^>]*)?>(.*?)</t[hd]>}).flatten

    it 'gives a map of records a row per name and a column per field' do
      html = CatalogTables.render(beasts)
      expect(cells(html).first(6)).to eq(%w[Name Size Speed Adjust Traits Parent])
      expect(html).to include('<th scope="row">Big Beast</th>')
    end

    it 'shows only the named columns, renamed and reached into' do
      html = CatalogTables.render(beasts, 'columns' => 'size=How big, traits.name', 'label' => 'Kind')
      expect(cells(html)).to eq(['Kind', 'How big', 'Traits', 'Beast', 'medium', 'scent', 'Big Beast', 'large', 'hide'])
    end

    it 'keeps only the listed rows, in the order listed' do
      html = CatalogTables.render(beasts, 'rows' => %w[big_beast], 'columns' => 'size')
      expect(cells(html)).to eq(['Name', 'Size', 'Big Beast', 'large'])
    end

    it 'starts a row from its parent: own values win, nested numbers add, lists join' do
      html = CatalogTables.render(beasts, 'inherit' => 'parent', 'rows' => %w[big_beast],
                                          'columns' => 'size, speed, adjust, traits.name')
      expect(cells(html).last(4)).to eq(['large', '30', 'int: -7, str: 4', 'scent, hide'])
    end

    it 'gives a map of lists a column per position' do
      html = CatalogTables.render({ 'hero' => [0, 1, 4], 'commoner' => [0, 4] }, 'index' => 'Tier')
      expect(cells(html)).to eq(['Name', 'Tier 0', 'Tier 1', 'Tier 2', 'Hero', '0', '1', '4', 'Commoner', '0', '4', '—'])
    end

    it 'keeps a map of lists to two columns until the positions are named' do
      html = CatalogTables.render({ 'sing' => %w[deception sense_motive] }, 'value' => 'Stands in for')
      expect(cells(html)).to eq(['Name', 'Stands in for', 'Sing', 'deception, sense_motive'])
    end

    it 'gives a map of plain values two columns' do
      html = CatalogTables.render({ 0 => 1, 1 => 4 }, 'label' => 'Tier', 'value' => 'Mana')
      expect(cells(html)).to eq(%w[Tier Mana 0 1 1 4])
    end

    it 'gives a list a position column' do
      html = CatalogTables.render(%w[a b], 'index' => 'Tier', 'value' => 'Formula')
      expect(cells(html)).to eq(%w[Tier Formula 0 a 1 b])
    end

    it 'gives a list of records a row per position' do
      html = CatalogTables.render([{ 'slow' => [1, 7], 'fast' => [2, 7] }], 'index' => 'Tier')
      expect(cells(html)).to eq(['Tier', 'Slow', 'Fast', '0', '1, 7', '2, 7'])
    end

    it 'marks a family name and leaves a name written for people alone' do
      html = CatalogTables.render({ 'craft_' => { 'a' => 1 }, 'Long sword' => { 'a' => 2 } })
      expect(html).to include('Craft (any)', 'Long sword')
    end

    it 'escapes what it prints' do
      html = CatalogTables.render({ 'x' => '<b>' })
      expect(html).to include('&lt;b&gt;')
      expect(html).not_to include('<b>')
    end

    it 'has no table for a plain value' do
      expect(CatalogTables.render(5)).to be_nil
      expect(CatalogTables.render({})).to be_nil
    end
  end

  describe '{{table: …}}' do
    it 'prints a catalog section' do
      html = sub('{{table: skills.yaml > Skills | label: Skill}}')
      expect(html).to start_with('<table class="catalog-table">')
      expect(html).to include('<th>Skill</th>', '<th scope="row">Athletics</th>')
    end

    it 'takes its rows from another part of the rules' do
      playable = catalog('creatures', 'character_creation.yaml')['Playable Races']
      html = sub('{{table: creatures_race.yaml | rows: character_creation.yaml > Playable Races | inherit: parent}}')
      expect(html.scan('<th scope="row">').size).to eq(playable.size)
      expect(html).to include(CatalogTables.humanize(playable.first))
      expect(html).not_to include('<th scope="row">Ogre</th>')
    end

    it 'takes its rows from a written list' do
      html = sub('{{table: creatures_race.yaml | rows: human, ogre | columns: size}}')
      expect(html.scan('<th scope="row">').size).to eq(2)
    end

    it 'renders an unknown table, and a value with no table shape, loudly' do
      expect(sub('{{table: skills.yaml > Nope}}')).to include('doc-missing-key', 'unknown table')
      expect(sub('{{table: Base Target Number}}')).to include('doc-missing-key', 'is not a table')
    end

    it 'comes through the markdown pass as one table between its paragraphs' do
      html = DocMarkdown.render(sub("Before.\n\n{{table: skills.yaml > Skills}}\n\nAfter."))
      expect(html.scan('<table').size).to eq(1)
      expect(html).to include('<p>Before.</p>', '<p>After.</p>')
    end
  end

  it 'leaves no unresolved path or table in any page of the book' do
    CommonDocs.concepts.each do |concept|
      %i[player dm].each do |audience|
        html = CommonDocs.render_design(concept, audience: audience).to_s
        expect(html).not_to include('doc-missing-key'), "#{concept.key} (#{audience}) has an unresolved {{…}}"
      end
    end
  end
end
