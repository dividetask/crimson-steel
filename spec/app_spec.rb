RSpec.describe 'Crimson Steel DM Tools' do
  describe 'Compendium (the one coded page)' do
    it 'renders the glossary' do
      get '/compendium'
      expect(last_response).to be_ok
      expect(last_response.body).to include('Glossary')
    end
  end

  describe 'pages that are not yet coded' do
    it 'shows "Not Yet Implemented" for a trimmed page' do
      get '/notes'
      expect(last_response.status).to eq(404)
      expect(last_response.body).to include('Not Yet Implemented')
    end

    it 'still renders the full menu so it stays navigable' do
      get '/store'
      expect(last_response.body).to include('Character Sheets')
      expect(last_response.body).to include('Compendium')
    end
  end

  describe 'Home' do
    it 'redirects to Character Sheets' do
      get '/'
      expect(last_response.status).to eq(302)
      expect(last_response.headers['Location']).to include('/character-sheets')
    end
  end
end
