RSpec.describe 'Compendium rendering' do
  describe 'navigation' do
    it 'lists each chapter overview, with Glossary pinned last' do
      labels = CompendiumDocs.nav_items.map { |i| i[:label] }
      expect(labels).to include('Check Resolution')
      expect(labels.last).to eq('Glossary')
    end
  end

  describe 'the Check Resolution overview' do
    let(:html) { CompendiumDocs.render_overview('check_resolution') }

    it 'substitutes a scalar config variable' do
      expect(html).to include('10') # {{Die Size}}
      expect(html).not_to include('{{')
      expect(html).not_to include('}}')
    end

    it 'computes a fully-numeric expression to a number' do
      # {{Maximum Dice Formula}} = Minimum Dice + Dice Range - 1 = 6 + 5 - 1
      expect(html).to include('10')
    end

    it 'renders a formula with config constants filled in and runtime vars kept' do
      expect(html).to include('cr-formula')
      expect(html).to include('Attribute / 2')
      expect(html).to include('Prowess')
      expect(html).to include('% 5') # Dice Range filled in
    end

    it 'turns [[keywords]] into clickable popups' do
      expect(html).to include('class="cr-kw"')
      expect(html).to include('cr-kw-pop-title')
      expect(html).to include('cr-kw-pop-body')
    end

    it 'skips ```test``` blocks entirely' do
      expect(html).not_to include('```test')
      expect(html).not_to include('Dice Cap: 3') # contents of a test block
    end

    it 'marks function sections with a badge and strips the @function line' do
      expect(html).to include('cr-fn-tag')
      expect(html).to include('ƒ function')
      expect(html).to include('Dice Cap')
      expect(html).not_to include('@function')
    end
  end

  describe 'keyword resolution' do
    it 'matches plurals against the singular glossary term' do
      idx = CompendiumDocs.glossary_index
      expect(idx).to have_key('check')
    end
  end

  describe 'formula resolution unit cases' do
    let(:config) { CompendiumDocs.load_config('check_resolution') }

    it 'keeps runtime variables symbolic' do
      text, formula = CompendiumDocs.resolve('Dice Cap Formula', config)
      expect(formula).to be(true)
      expect(text).to include('Attribute')
      expect(text).to include('Prowess')
      expect(text).not_to include('<')
    end

    it 'evaluates a constant-only expression to a number' do
      text, formula = CompendiumDocs.resolve('Maximum Dice Formula', config)
      expect(formula).to be(false)
      expect(text).to eq('10')
    end

    it 'substitutes a scalar key' do
      text, formula = CompendiumDocs.resolve('Die Size', config)
      expect(formula).to be(false)
      expect(text).to eq('10')
    end
  end

  describe 'the Glossary view' do
    it 'renders definitions' do
      get '/compendium?view=glossary'
      expect(last_response).to be_ok
      expect(last_response.body).to include('glossary-term')
      expect(last_response.body).to include('Check')
    end
  end

  describe 'the default Compendium view' do
    it 'opens on the first chapter overview' do
      get '/compendium'
      expect(last_response).to be_ok
      expect(last_response.body).to include('Dice Cap')
    end
  end
end
