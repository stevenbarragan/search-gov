# frozen_string_literal: true

describe SearchesController do
  let(:affiliate) { affiliates(:usagov_affiliate) }

  before do
    affiliate.use_redesigned_results_page = false
    affiliate.save(validate: false)
  end

  context 'when showing a new search' do
    render_views
    context 'when searching in English' do
      before do
        get :index, params: { query: 'social security', page: 4, affiliate: 'usagov' }
        @search = assigns[:search]
        @page_title = assigns[:page_title]
      end

      it 'should assign to search_options a Hash with only Symbol keys' do
        expect(@controller.view_assigns['search_options'].keys.map(&:class).uniq).to eq([Symbol])
      end

      it 'should assign the USA.gov affiliate as the default affiliate' do
        expect(assigns[:affiliate]).to eq(affiliates(:usagov_affiliate))
      end

      it 'should render the template' do
        expect(response).to render_template 'index'
        expect(response).to render_template 'layouts/searches'
      end

      it 'should assign the query as the page title' do
        expect(@page_title).to eq('social security - USA.gov Search Results')
      end

      it 'should show a custom title for the results page' do
        expect(response.body).to match(/social security - USA.gov Search Results/)
      end

      it 'should set the query in the Search model' do
        expect(@search.query).to eq('social security')
      end

      it 'should set the page' do
        expect(@search.page).to eq(4)
      end

      it 'should load results for a keyword query' do
        expect(@search).not_to be_nil
        expect(@search.results).not_to be_nil
      end

      it { is_expected.to assign_to(:search_params).with(
        hash_including(affiliate: affiliate.name, query: 'social security')) }
    end

    context 'when searching in English (redesign)' do
      before do
        get :index, params: { query: 'social security', affiliate: 'redesigned_usagov' }
      end

      it 'renders the React templates' do
        expect(response).to render_template 'index_redesign'
        expect(response).to render_template 'layouts/searches_redesign'
      end

      it 'renders the referrer policy' do
        expect(response.body).to match(/meta content='no-referrer-when-downgrade' name='referrer'/)
      end
    end

    context 'when searching on a Spanish site' do
      it 'assigns locale to :es' do
        expect(I18n).to receive(:locale=).with(:es)
        get :index,
            params: {
              query: 'social security',
              page: 4,
              affiliate: 'gobiernousa'
            }
      end
    end
  end

  context 'when affiliate is not valid' do
    before { get :index, params: { query: 'gov', affiliate: { 'foo' => 'bar' } } }
    it { is_expected.to redirect_to 'https://www.usa.gov/search-error' }
  end

  context 'when the affiliate is not active' do
    let(:affiliate) { affiliates(:inactive_affiliate) }

    before do
      affiliate.use_redesigned_results_page = false
      affiliate.save(validate: false)
      get :index,
          params: {
            query: 'gov',
            affiliate: affiliate.name
          }
    end

    it { is_expected.to respond_with(:success) }
    it { is_expected.to render_template(:inactive_affiliate) }
    it { is_expected.to render_template('layouts/application') }

    it 'sets the correct page title' do
      expect(assigns[:page_title]).to eq("Search Temporarily Unavailable - #{affiliate.display_name}")
    end
  end

  context 'when searching with non scalar query' do
    it 'should not blow up if query is not a string' do
      get :index, params: { query: { 'foo' => 'bar' }, affiliate: 'usagov' }
      expect(assigns[:search].query).to be_blank
    end
  end

  context 'searching on a routed keyword' do
    let(:affiliate) { affiliates(:basic_affiliate) }

    context 'referrer does not match redirect url' do
      it 'redirects to the proper url' do
        get :index, params: { query: 'moar unclaimed money', affiliate: affiliate.name }
        expect(response).to redirect_to 'https://www.usa.gov/unclaimed_money'
      end

      it 'logs the impression' do
        expect(RoutedQueryImpressionLogger).to receive(:log)
        get :index,
            params: {
              query: 'moar unclaimed money',
              affiliate: affiliate.name
            }
      end
    end

    context 'referrer matches redirect url' do
      let(:ref_url) { 'http://www.gov.gov/foo.html' }
      let(:rq_url) { 'http://www.gov.gov/foo.html' }

      shared_examples_for 'a routed query that matches the referrer' do
        before do
          routed_query = affiliate.routed_queries.build(url: rq_url, description: 'testing')
          routed_query.routed_query_keywords.build(keyword: 'foo bar')
          routed_query.save!
          request.env['HTTP_REFERER'] = ref_url
          get :index,
              params: {
                query: 'foo bar',
                affiliate: affiliate.name
              }
        end

        it { is_expected.to render_template(:index) }
      end

      it_should_behave_like 'a routed query that matches the referrer'

      context 'when the match is exact except that the referring URL is http and the routed query URL is https' do
        let(:rq_url) { 'https://www.gov.gov/foo.html' }

        it_should_behave_like 'a routed query that matches the referrer'
      end

      context 'when the match is exact except that the referring URL is https and the routed query URL is http' do
        let(:ref_url) { 'https://www.gov.gov/foo.html' }

        it_should_behave_like 'a routed query that matches the referrer'
      end
    end
  end

  context 'when affiliate gets i14y results' do
    let(:affiliate) { affiliates(:basic_affiliate) }
    let(:i14y_search) { double(I14ySearch, query: 'gov', modules: %w(I14Y), diagnostics: {}) }

    before do
      expect(Affiliate).to receive(:find_by_name).and_return(affiliate)
      affiliate.gets_i14y_results = true
      expect(I14ySearch).to receive(:new).and_return(i14y_search)
      expect(i14y_search).to receive(:run)
      get :index, params: { query: 'gov', affiliate: affiliate.name }
    end

    it { is_expected.to assign_to(:affiliate).with(affiliate) }

    it 'should assign various variables' do
      expect(assigns[:page_title]).to match(/gov/)
      expect(assigns[:search_vertical]).to eq(:i14y)
    end

    it { is_expected.to assign_to(:search_params).with(
      hash_including(affiliate: affiliate.name, query: 'gov')) }

    it { is_expected.to render_template(:i14y) }

  end

  context 'when affiliate is using SearchGov' do
    let(:affiliate) { affiliates(:basic_affiliate) }
    let(:i14y_search) { double(I14ySearch, query: 'gov', modules: %w(I14Y), diagnostics: {}) }

    before do
      expect(Affiliate).to receive(:find_by_name).and_return(affiliate)
      affiliate.search_engine = 'SearchGov'
      expect(I14ySearch).to receive(:new).and_return(i14y_search)
      expect(i14y_search).to receive(:run)
      get :index, params: { query: 'gov', affiliate: affiliate.name }
    end

    it { is_expected.to assign_to(:affiliate).with(affiliate) }

    it 'should assign various variables' do
      expect(assigns[:page_title]).to match(/gov/)
      expect(assigns[:search_vertical]).to eq(:i14y)
    end

    it { is_expected.to assign_to(:search_params).with(
      hash_including(affiliate: affiliate.name, query: 'gov')) }

    it { is_expected.to render_template(:i14y) }
  end

  context 'when handling a valid affiliate search request' do
    render_views
    let(:affiliate) { affiliates(:basic_affiliate) }

    before do
      get :index,
          params: {
            affiliate: affiliate.name,
            query: '<b>thunder & lightning</b>'
          }
      @search = assigns[:search]
      @page_title = assigns[:page_title]
    end

    it { is_expected.to respond_with(:success) }
    it { is_expected.to assign_to :affiliate }
    it { is_expected.to assign_to :page_title }

    it 'should sanitize the query term' do
      expect(@search.query).to eq('thunder & lightning')
    end

    it 'should render the template' do
      expect(response).to render_template 'index'
      expect(response).to render_template 'layouts/searches'
    end

    it 'sets an affiliate page title' do
      expect(@page_title).to eq('thunder & lightning - NPS Site Search Results')
    end
  end

  context 'when the affiliate locale is set to Spanish' do
    before do
      affiliate = affiliates(:gobiernousa_affiliate)
      get :index,
          params: {
            affiliate: affiliate.name,
            query: 'weather',
            locale: 'en'
          }
    end
    after { I18n.locale = I18n.default_locale }

    it 'should override/ignore the HTTP locale param and set locale to Spanish' do
      expect(I18n.locale.to_s).to eq('es')
    end
  end

  context 'when searching via the API' do
    render_views

    context 'when searching normally' do
      before do
        get :index, params: { query: 'weather', affiliate: 'usagov' }, format: 'json'
        @search = assigns[:search]
      end

      it 'should serialize the results into JSON' do
        expect(response.body).to match(/total/)
        expect(response.body).to match(/startrecord/)
        expect(response.body).to match(/endrecord/)
      end
    end

    context 'when some error is returned' do
      before do
        get :index, params: { query: 'a' * 1001,  affiliate: 'usagov' }, format: 'json'
        @search = assigns[:search]
      end

      it 'should serialize an error into JSON' do
        expect(response.body).to match(/error/)
        expect(response.body).to match(/#{I18n.translate :too_long}/)
      end
    end
  end

  context 'when handling an invalid affiliate search request' do
    before do
      get :index,
          params: {
            affiliate: 'doesnotexist.gov',
            query: 'weather'
          }
    end

    it { is_expected.to redirect_to 'https://www.usa.gov/search-error' }
  end

  context 'when handling any affiliate search request with a JSON format' do
    render_views
    before do
      get :index,
          params: {
            affiliate: affiliates(:power_affiliate).name,
            query: 'weather'
          },
          format: 'json'
    end

    it 'should serialize the results into JSON' do
      expect(response.body).to match(/total/)
      expect(response.body).to match(/startrecord/)
      expect(response.body).to match(/endrecord/)
    end
  end

  context 'highlighting' do
    context 'when a client requests results without highlighting' do
      before do
        get :index,
            params: {
              query: 'obama',
              hl: 'false',
              affiliate: 'usagov'
            }
      end

      it 'should set the highlighting option to false' do
        @search_options = assigns[:search_options]
        expect(@search_options[:enable_highlighting]).to be false
      end
    end

    context 'when a client requests result with highlighting' do
      before do
        get :index,
            params: {
              query: 'obama',
              hl: 'true',
              affiliate: 'usagov'
            }
      end

      it 'should set the highlighting option to true' do
        @search_options = assigns[:search_options]
        expect(@search_options[:enable_highlighting]).to be true
      end
    end

    context 'when a client does not specify highlighting' do
      before do
        get :index,
            params: {
              query: 'obama',
              affiliate: 'usagov'
            }
      end

      it 'should set the highlighting option to true' do
        @search_options = assigns[:search_options]
        expect(@search_options[:enable_highlighting]).to be true
      end
    end
  end

  describe '#advanced' do
    before { get :advanced, params: { affiliate: 'usagov' } }

    it { is_expected.to assign_to(:page_title).with_kind_of(String) }
  end

  describe '#docs' do
    let(:affiliate) { affiliates(:basic_affiliate) }
    let(:dc) { mock_model(DocumentCollection) }
    let(:docs_params) do
      { query: 'gov', affiliate: affiliate.name, dc: 100 }
    end

    context 'when DocumentCollection exists' do
      let(:site_search) { double(SiteSearch, query: 'gov', modules: %w(BWEB), diagnostics: {}) }

      before do
        allow(dc).to receive(:too_deep_for_bing?).and_return(false)
        expect(Affiliate).to receive(:find_by_name).at_least(:once).and_return(affiliate)
        allow(affiliate).to receive_message_chain(:document_collections, :find_by_id).and_return(dc)
        expect(SiteSearch).to receive(:new).with(hash_including(dc: '100', per_page: 20)).and_return(site_search)
        expect(site_search).to receive(:run)
        get :docs, params: docs_params
      end

      it { is_expected.to assign_to(:affiliate).with(affiliate) }

      it 'should assign various variables' do
        expect(assigns[:page_title]).to match(/gov/)
        expect(assigns[:search_vertical]).to eq(:docs)
        expect(assigns[:form_path]).to eq(docs_search_path)
      end

      it { is_expected.to assign_to(:search_params).with(
        hash_including(affiliate: affiliate.name, query: 'gov')) }

      it { is_expected.to render_template(:docs) }

      context 'when document collection max depth is >= 3' do
        let(:i14y_search) { double(I14ySearch, query: 'gov', modules: %w(I14Y), diagnostics: {}) }

        before do
          allow(dc).to receive(:too_deep_for_bing?).and_return(true)
        end

        it 'triggers an I14y search' do
          expect(I14ySearch).to receive(:new).and_return(i14y_search)
          expect(i14y_search).to receive(:run)
          get :docs,
              params: {
                query: 'gov',
                affiliate: affiliate.name,
                dc: 100
              }
        end
      end

      context 'when searching with a date range' do
        let(:docs_params) do
          {
            query: 'by date',
            affiliate: affiliate.name,
            dc: 100,
            since_date: '10/1/2012',
            until_date: '10/15/2012',
            sort_by: 'r',
            tbs: 'w'
          }
        end

        it { is_expected.to assign_to(:search_options).
             with(hash_including(since_date: '10/1/2012', until_date:'10/15/2012', sort_by: 'r', tbs: 'w')) }
      end
    end

    context 'when page number is specified' do
      let(:site_search) { double(SiteSearch, query: 'pdf', modules: [], diagnostics: {}) }

      before do
        expect(Affiliate).to receive(:find_by_name).and_return(affiliate)
        allow(dc).to receive(:too_deep_for_bing?).and_return(false)
        allow(affiliate).to receive_message_chain(:document_collections, :find_by_id).and_return(dc)
        expect(SiteSearch).to receive(:new).with(hash_including(dc: '100')).and_return(site_search)
        expect(site_search).to receive(:run)
        get :docs,
            params: {
              query: 'pdf',
              affiliate: affiliate.name,
              dc: 100,
              page: 3
            }
      end

      specify { expect(assigns[:search_options][:page]).to eq('3') }
    end

    context 'when DocumentCollection does not exist' do
      let(:web_search) { double(WebSearch, query: 'gov', modules: [], diagnostics: {}) }

      before do
        expect(Affiliate).to receive(:find_by_name).and_return(affiliate)
        allow(affiliate).to receive_message_chain(:document_collections, :find_by_id).and_return(nil)
        expect(WebSearch).to receive(:new).with(hash_including(dc: '100', per_page: 20)).and_return(web_search)
        expect(web_search).to receive(:run)
        expect(SiteSearch).not_to receive(:new)
        get :docs,
            params: {
              query: 'pdf',
              affiliate: affiliate.name,
              dc: 100
            }
      end

      it { is_expected.to assign_to(:affiliate).with(affiliate) }
    end

    context 'when params[:dc] is not a valid number' do
      let(:web_search) { double(WebSearch, query: 'gov', modules: [], diagnostics: {}) }

      before do
        expect(Affiliate).to receive(:find_by_name).and_return(affiliate)
        allow(affiliate).to receive_message_chain(:document_collections, :find_by_id).with(nil).and_return(nil)
        expect(WebSearch).to receive(:new).with(hash_including(query: 'pdf')).and_return(web_search)
        expect(web_search).to receive(:run)
        expect(SiteSearch).not_to receive(:new)
        get :docs,
            params: {
              query: 'pdf',
              affiliate: affiliate.name,
              dc: { 'foo': 'bar' }
            }
      end

      it { is_expected.to assign_to(:affiliate).with(affiliate) }
    end

    context 'when the affiliate uses the SearchGov engine' do
      let(:affiliate) { affiliates(:basic_affiliate) }
      let(:i14y_search) { double(I14ySearch, query: 'gov', modules: %w(I14Y), diagnostics: {}) }

      before do
        expect(Affiliate).to receive(:find_by_name).and_return(affiliate)
        affiliate.search_engine = 'SearchGov'
        expect(I14ySearch).to receive(:new).and_return(i14y_search)
        expect(i14y_search).to receive(:run)
        get :docs,
            params: {
              query: 'gov',
              affiliate: affiliate.name,
              dc: 100
            }
      end

      it { is_expected.to render_template(:i14y) }

      it 'should assign various variables' do
        expect(assigns[:page_title]).to match(/gov/)
        expect(assigns[:search_vertical]).to eq(:docs)
        expect(assigns[:form_path]).to eq(docs_search_path)
      end
    end
  end

  describe '#news' do
    let(:affiliate) { affiliates(:basic_affiliate) }

    before do
      NewsItem.all.each { |news_item| news_item.save! }
      ElasticNewsItem.commit
    end

    it 'should assign page title, vertical, form_path, and search members' do
      get :news,
          params: {
            query: 'element',
            affiliate: affiliate.name,
            channel: rss_feeds(:white_house_blog).id,
            tbs: 'w',
            page: '1',
            per_page: '5'
          }
      expect(assigns[:page_title]).to eq("element - #{affiliate.display_name} Search Results")
      expect(assigns[:search_vertical]).to eq(:news)
      expect(assigns[:form_path]).to eq(news_search_path)
      expect(assigns[:search]).to be_an_instance_of(NewsSearch)
    end

    it 'finds news items that match the query for the affiliate' do
      get :news,
          params: {
            query: 'element',
            affiliate: affiliate.name,
            channel: rss_feeds(:white_house_blog).id,
            tbs: 'w'
          }

      expect(assigns[:search].total).to eq(1)
      expect(assigns[:search].results.first).to eq(news_items(:item1))
      expect(assigns[:search].results.first.title).to eq("News \uE000element\uE001 1")
      expect(assigns[:search].results.first.link).to eq('http://some.agency.gov/news/1')
      expect(assigns[:search].results.first.published_at).to be_present
      expect(assigns[:search].results.first.description).to eq("News \uE000element\uE001 1 has a description")
    end

    context 'when the affiliate does not exist' do
      before do
        get :news,
            params: {
              query: 'element',
              affiliate: 'donotexist',
              channel: rss_feeds(:white_house_blog).id,
              tbs: 'w'
            }
      end

      it { is_expected.to redirect_to 'https://www.usa.gov/search-error' }
    end

    context 'when the query is blank and total is > 0' do
      before do
        get :news,
            params: {
              query: '',
              affiliate: affiliate.name,
              channel: rss_feeds(:white_house_blog).id,
              tbs: 'w'
            }
      end

      it { is_expected.to assign_to(:page_title).with('White House Blog - NPS Site Search Results') }
    end

    context 'when handling an array parameter' do
      before do
        get :news,
            params: {
              'affiliate': affiliate.name,
              'channel': rss_feeds(:white_house_blog).id,
              'query': ['loren']
            }
      end

      it 'should render the template' do
        expect(response).to render_template 'news'
        expect(response).to render_template 'layouts/searches'
      end
    end

    context 'when searching with tbs' do
      before do
        expect(Affiliate).to receive(:find_by_name).with(affiliate.name).and_return(affiliate)
        news_search = double(NewsSearch,
                           query: 'element',
                           rss_feed: rss_feeds(:white_house_blog),
                           modules: [],
                           tbs: 'w',
                           diagnostics: {})
        expect(news_search).to receive(:is_a?).with(FilterableSearch).and_return(true)
        expect(news_search).to receive(:is_a?).with(NewsSearch).and_return(true)
        expect(NewsSearch).to receive(:new).with(hash_including(tbs: 'w', per_page: 20)).and_return(news_search)
        expect(news_search).to receive(:run)

        get :news,
            params: {
              query: 'element',
              affiliate: affiliate.name,
              channel: rss_feeds(:white_house_blog).id,
              tbs: 'w',
              sort_by: 'r',
              contributor: 'The President',
              publisher: 'The White House',
              subject: 'Economy'
            }
      end

      it { is_expected.to assign_to(:search_params).with(
        hash_including(affiliate: affiliate.name,
                       query: 'element',
                       channel: rss_feeds(:white_house_blog).id,
                       tbs: 'w',
                       sort_by: 'r',
                       contributor: 'The President',
                       publisher: 'The White House',
                       subject: 'Economy')) }
    end

    context 'when searching with a date range' do
      let(:channel_id) { rss_feeds(:white_house_blog).id }

      before do
        expect(Affiliate).to receive(:find_by_name).with(affiliate.name).and_return(affiliate)
        news_search = double(NewsSearch,
                           query: 'element',
                           rss_feed: rss_feeds(:white_house_blog),
                           modules: [],
                           tbs: nil,
                           since: Time.parse('2012-10-1'),
                           until: Time.parse('2012-10-15'),
                           diagnostics: {})
        expect(news_search).to receive(:is_a?).with(FilterableSearch).and_return(true)
        expect(news_search).to receive(:is_a?).with(NewsSearch).and_return(true)
        expect(NewsSearch).to receive(:new).
            with(hash_including(since_date: '10/1/2012', until_date:'10/15/2012')).
            and_return(news_search)
        expect(news_search).to receive(:run)

        get :news,
            params: {
              query: 'element',
              affiliate: affiliate.name,
              channel: channel_id,
              tbs: 'w',
              since_date:
                '10/1/2012',
              until_date:
                '10/15/2012'
            }
      end

      it { is_expected.to assign_to(:affiliate).with(affiliate) }
      it { is_expected.to assign_to(:search_options).with(hash_including(since_date: '10/1/2012', until_date:'10/15/2012')) }
      it { is_expected.to assign_to(:search_params).with(
        hash_including(affiliate: affiliate.name,
                       query: 'element',
                       channel: rss_feeds(:white_house_blog).id,
                       since_date: '10/01/2012',
                       until_date: '10/15/2012')) }
    end

    describe 'rendering the view' do
      render_views

      it 'should render the template' do
        get :news,
            params: {
              query: 'element',
              affiliate: affiliate.name,
              channel: rss_feeds(:white_house_blog).id,
              tbs: 'w'
            }
        expect(response).to render_template 'news'
        expect(response).to render_template 'layouts/searches'
      end
    end
  end
end
