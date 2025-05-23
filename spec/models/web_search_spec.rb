# frozen_string_literal: true

describe WebSearch do
  let(:affiliate) { affiliates(:usagov_affiliate) }
  let(:valid_options) do
    { query: 'government', affiliate: affiliate }
  end

  describe '.new' do
    it 'has a settable query' do
      search = described_class.new(valid_options)
      expect(search.query).to eq('government')
    end

    it 'has a settable affiliate' do
      search = described_class.new(valid_options)
      expect(search.affiliate).to eq(affiliate)
    end

    it 'does not require a query' do
      expect { described_class.new(affiliate: affiliate) }.not_to raise_error
    end

    it 'ignores invalid params' do
      search = described_class.new(valid_options.merge(page: { foo: 'bar' }))
      expect(search.page).to eq(1)
    end

    it 'ignores params outside the allowed range' do
      search = described_class.new(valid_options.merge(page: -1))
      expect(search.page).to eq(Pageable::DEFAULT_PAGE)
    end

    it 'sets matching site limits' do
      affiliate.site_domains.create!(domain: 'foo.com')
      affiliate.site_domains.create!(domain: 'bar.gov')
      search = described_class.new(query: 'government', affiliate: affiliate, site_limits: 'foo.com/subdir1 foo.com/subdir2 include3.gov')
      expect(search.matching_site_limits).to eq(%w[foo.com/subdir1 foo.com/subdir2])
    end
  end

  describe '#cache_key' do
    let(:valid_options) do
      { query: 'government', affiliate: affiliate, page: 5 }
    end

    it 'outputs a key based on the query, options (including affiliate id), and search engine parameters' do
      expect(described_class.new(valid_options).cache_key).to eq("government (site:gov OR site:mil):{:query=>\"government\", :page=>5, :affiliate_id=>#{affiliate.id}}:bing_v7")
    end
  end

  describe 'instrumenting search engine calls' do
    context 'when BingV7 is the engine' do
      before do
        affiliate.search_engine = 'BingV7'
        valid_options = { query: 'government', affiliate: affiliate }
        bing_search = BingV7WebSearch.new(valid_options)
        allow(BingV7WebSearch).to receive(:new).and_return bing_search
        allow(bing_search).to receive(:execute_query)
      end

      it 'instruments the call to the search engine with the proper action.service namespace and query param hash' do
        expect(affiliate).to be_bing_v7_engine
        expect(ActiveSupport::Notifications).to receive(:instrument).
          with('bing_v7_web_search.usasearch', hash_including(query: hash_including(term: 'government')))
        described_class.new(valid_options).send(:search)
      end
    end
  end

  describe '#run' do
    context 'when searching with a blacklisted query term' do
      let(:search) do
        described_class.new(query: Search::BLACKLISTED_QUERIES.sample, affiliate: affiliate)
      end

      it 'returns false when searching' do
        expect(search.run).to be false
      end

      it 'has 0 results' do
        search.run
        expect(search.results.size).to be_zero
      end

      it 'sets error message' do
        search.run
        expect(search.error_message).to eq(I18n.t(:empty_query))
      end
    end

    context 'when searching with really long queries' do
      let(:search) do
        described_class.new(query: 'X' * (Search::MAX_QUERYTERM_LENGTH + 1), affiliate: affiliate)
      end

      it 'returns false when searching' do
        expect(search.run).to be false
      end

      it 'has 0 results' do
        search.run
        expect(search.results.size).to be_zero
      end

      it 'sets error message' do
        search.run
        expect(search.error_message).to eq(I18n.t(:too_long))
      end
    end

    context 'when paginating' do
      let(:affiliate) { affiliates(:basic_affiliate) }

      it 'defaults to page 1 if no valid page number was specified' do
        expect(described_class.new(query: 'government', affiliate: affiliate).page).to eq(Pageable::DEFAULT_PAGE)
        expect(described_class.new(query: 'government', affiliate: affiliate, page: '').page).to eq(Pageable::DEFAULT_PAGE)
        expect(described_class.new(query: 'government', affiliate: affiliate, page: 'string').page).to eq(Pageable::DEFAULT_PAGE)
      end

      it 'sets the page number' do
        search = described_class.new(query: 'government', affiliate: affiliate, page: 2)
        expect(search.page).to eq(2)
      end
    end

    describe 'logging module impressions' do
      let(:search) do
        described_class.new(query: 'government', affiliate: affiliates(:basic_affiliate))
      end

      before do
        allow(search).to receive(:search)
        allow(search).to receive(:handle_response)
        allow(search).to receive(:populate_additional_results)
        allow(search).to receive(:module_tag).and_return 'BWEB'
        allow(search).to receive(:spelling_suggestion).and_return 'foo'
      end

      it 'assigns module_tag to BWEB' do
        search.run
        expect(search.module_tag).to eq('BWEB')
      end
    end

    describe 'populating additional results' do
      let(:search) do
        described_class.new(query: 'english', affiliate: affiliates(:non_existent_affiliate), geoip_info: 'test')
      end

      it 'gets the info from GovboxSet' do
        expect(GovboxSet).to receive(:new).with('english', affiliates(:non_existent_affiliate), 'test', site_limits: []).and_return nil
        search.run
      end
    end

    # TODO: remove this along with the rest of the Bing stuff being deprecated
    #       this temporary spec is only here for code coverage
    context 'when the affiliate has Bing results' do
      subject(:search) do
        affiliate = affiliates(:usagov_affiliate)
        affiliate.search_engine = 'BingV7'
        described_class.new(query: 'english', affiliate: affiliate)
      end

      it 'assigns BWEB as the module_tag' do
        search.run
        expect(search.module_tag).to eq('BWEB')
      end
    end

    context 'when the affiliate has no Bing results' do
      let(:non_affiliate) { affiliates(:non_existent_affiliate) }
      let(:search) { described_class.new(query: 'no_results', affiliate: non_affiliate) }

      before do
        bing_api_url = "#{BingV7WebSearch::API_HOST}#{BingV7WebSearch::API_ENDPOINT}"
        stub_request(:get, /#{bing_api_url}.*no_results/).
          to_return(status: 200, body: '{}')
      end

      context 'when the affiliate has indexed documents' do
        before do
          ElasticIndexedDocument.recreate_index
          non_affiliate.site_domains.create(domain: 'nonsense.com')
          non_affiliate.indexed_documents.destroy_all
          1.upto(25) do |index|
            non_affiliate.indexed_documents << IndexedDocument.new(title: "Indexed Result no_result #{index}",
                                                                   url: "http://nonsense.com/#{index}.html",
                                                                   description: 'This is an indexed result no_result.',
                                                                   last_crawl_status: IndexedDocument::OK_STATUS)
          end
          ElasticIndexedDocument.commit
        end

        it 'fills the results with the Odie docs' do
          search.run
          expect(search.total).to eq(25)
          expect(search.startrecord).to eq(1)
          expect(search.endrecord).to eq(20)
          expect(search.results.first['unescapedUrl']).to match(/nonsense.com/)
          expect(search.results.last['unescapedUrl']).to match(/nonsense.com/)
          expect(search.module_tag).to eq('AIDOC')
        end
      end

      context 'when the IndexedDocuments search returns nil' do
        before do
          non_affiliate.boosted_contents.destroy_all
          allow(ElasticIndexedDocument).to receive(:search_for).and_return nil
        end

        it 'returns a search with a zero total' do
          search.run
          expect(search.total).to eq(0)
          expect(search.results).not_to be_nil
          expect(search.results).to be_empty
          expect(search.startrecord).to be_nil
          expect(search.endrecord).to be_nil
        end

        it 'still returns true when searching' do
          expect(search.run).to be true
        end

        it 'populates additional results' do
          expect(search).to receive(:populate_additional_results).and_return true
          search.run
        end
      end

      context 'when there is an orphan document in the Odie index' do
        before do
          ElasticIndexedDocument.recreate_index
          non_affiliate.indexed_documents.destroy_all
          odie = non_affiliate.indexed_documents.create!(title: 'PDF Title',
                                                         description: 'PDF Description',
                                                         url: 'http://nonsense.gov/pdf1.pdf',
                                                         doctype: 'pdf',
                                                         last_crawl_status: IndexedDocument::OK_STATUS)
          ElasticIndexedDocument.commit
          odie.delete
        end

        it 'returns with zero results' do
          search = described_class.new(query: 'no_results', affiliate: non_affiliate)
          search.run
          expect(search.results).to be_blank
        end
      end
    end

    describe 'ODIE backfill' do
      context 'when we want X Bing results from page Y and there are X of them' do
        let(:search) { described_class.new(query: 'english', affiliate: affiliate) }

        before do
          search.run
        end

        it 'returns the X Bing results' do
          expect(search.total).to be > 1000
          expect(search.results.size).to eq(20)
          expect(search.startrecord).to eq(1)
          expect(search.endrecord).to eq(20)
        end
      end

      context 'when we want X Bing results from page Y and there are 0 <= n < X of them' do
        let(:search) do
          described_class.new(query: 'odie backfill', affiliate: affiliate, page: page)
        end
        let(:page) { 1 }

        before do
          affiliate.search_engine = 'BingV7'
          ElasticIndexedDocument.recreate_index

          bing_api_url = "#{BingV7WebSearch::API_HOST}#{BingV7WebSearch::API_ENDPOINT}"
          page1_6results = Rails.root.join('spec/fixtures/json/bing_v7/web_search/page1_6results.json').read
          stub_request(:get, /#{bing_api_url}.*odie backfill/).
            to_return(status: 200, body: page1_6results)
        end

        context 'when the affiliate has social image feeds and there are Odie results' do
          before do
            21.times do |index|
              affiliate.indexed_documents.create!(
                title: "odie backfill #{index}",
                description: "odie backfill #{index}",
                url: "http://nonsense.gov/#{index}",
                last_crawl_status: IndexedDocument::OK_STATUS
              )
            end
            ElasticIndexedDocument.commit
            allow(affiliate).to receive(:has_social_image_feeds?).and_return true

            search.run
          end

          context 'when returning the first page with commercial results' do
            it 'indicates via the search.total that there is another page of results' do
              expect(search.total).to be >= 20
              expect(search.results.size).to be == 6
              expect(search.startrecord).to be == 1
              expect(search.endrecord).to be == 6
            end
          end

          context 'when returning the second page' do
            let(:page) { 2 }

            it 'returns the Odie results' do
              expect(search.results.sample['title']).to match(/odie/)
              expect(search.total).to be >= 20
              expect(search.results.size).to be == 20
              expect(search.startrecord).to be == 21
              expect(search.endrecord).to be == 40
            end
          end

          context 'when returning the third page' do
            let(:page) { 3 }

            it 'returns the remaining Odie result' do
              expect(search.results.sample['title']).to match(/odie/)
              expect(search.total).to be >= 20
              expect(search.results.size).to be == 1
              expect(search.startrecord).to be == 41
              expect(search.endrecord).to be == 41
            end
          end
        end

        context 'when there are no Odie results' do
          before do
            search.run
          end

          it 'returns the X Bing results' do
            expect(search.total).to be == 6
            expect(search.results.size).to be == 6
            expect(search.startrecord).to be == 1
            expect(search.endrecord).to be == 6
          end
        end
      end
    end

    context 'when the affiliate has site domains and excluded domains' do
      let(:affiliate) do
        Affiliate.create!(name: 'nasa', display_name: 'Nasa', search_engine: 'BingV7')
      end
      let(:search) { described_class.new(affiliate: affiliate, query: query) }

      before do
        affiliate.site_domains.create!(domain: included_domain)
        affiliate.excluded_domains.create!(domain: excluded_domain)
        search.run
      end

      context 'when a subdirectory is excluded' do
        let(:included_domain) { 'justice.gov' }
        let(:excluded_domain) { 'justice.gov/legal-careers' }
        let(:query) { 'legal careers' }

        it 'includes the included domains' do
          search.results.each do |result|
            expect(result['unescapedUrl']).to match(/justice.gov/)
          end
        end

        it 'excludes the excluded domains', skip: 'Pending: https://www.pivotaltracker.com/story/show/139210497' do
          search.results.each do |result|
            expect(result['unescapedUrl']).not_to match(%r{justice.gov/legal-careers})
          end
        end
      end

      context 'when a subdomain is excluded' do
        let(:included_domain) { 'nasa.gov' }
        let(:excluded_domain) { 'mars.nasa.gov' }
        let(:query) { 'mars' }

        it 'includes the included domains' do
          search.results.each do |result|
            expect(result['unescapedUrl']).to match(/nasa.gov/)
          end
        end

        it 'excludes the excluded domains', skip: 'Pending: https://www.pivotaltracker.com/story/show/139210497' do
          search.results.each do |result|
            expect(result['unescapedUrl']).not_to match(/mars.nasa.gov/)
          end
        end
      end

      context 'when a top-level domain is included' do
        let(:included_domain) { '.gov' }
        let(:excluded_domain) { 'nasa.gov' }
        let(:query) { 'mars' }

        it 'includes the included domains' do
          search.results.each do |result|
            expect(result['unescapedUrl']).to match(/.gov/)
          end
        end

        it 'excludes the excluded domains', skip: 'Pending: https://www.pivotaltracker.com/story/show/139210497' do
          search.results.each do |result|
            expect(result['unescapedUrl']).not_to match(/nasa.gov/)
          end
        end
      end
    end
  end

  describe '#as_json' do
    let(:affiliate) { affiliates(:non_existent_affiliate) }
    let(:search) { described_class.new(query: 'english', affiliate: affiliate) }

    it 'generates a JSON representation of total, start and end records, and search results' do
      search.run
      json = search.to_json
      expect(json).to match(/total/)
      expect(json).to match(/startrecord/)
      expect(json).to match(/endrecord/)
      expect(json).to match(/results/)
    end

    context 'when an error occurs' do
      before do
        search.run
        search.instance_variable_set(:@error_message, 'Some error')
      end

      it 'outputs an error if an error is detected' do
        json = search.to_json
        expect(json).to match(/"error":"Some error"/)
      end
    end

    context 'when boosted contents are present' do
      before do
        affiliate.boosted_contents.create!(title: 'boosted english content', url: 'http://nonsense.gov',
                                           description: 'english description', status: 'active', publish_start_on: Date.current)
        ElasticBoostedContent.commit
        search.run
      end

      it 'outputs boosted results' do
        json = search.to_json
        expect(json).to match(%r{boosted <strong>english</strong> content})
      end
    end

    context 'when jobs are present' do
      let(:jobs_array) do
        jobs_array = []
        jobs_array << Hashie::Mash.new(
          id: 'usajobs:12345',
          position_title: 'Physician  (Primary Care - Women Clinic)',
          organization_name: 'Veterans Affairs, Veterans Health Administration',
          rate_interval_code: 'PA',
          minimum_pay: 60_000,
          maximum_pay: 70_000,
          start_date: '2012-10-05',
          end_date: '2023-10-04',
          locations: [
            'Memphis, TN', 'Lansing, MI'
          ],
          url: 'https://www.usajobs.gov/GetJob/ViewDetails/12345'
        )
        jobs_array << Hashie::Mash.new(
          id: 'usajobs:23456',
          position_title: 'PHYSICAL THERAPIST',
          organization_name: 'Veterans Affairs, Veterans Health Administration',
          rate_interval_code: 'PA',
          minimum_pay: 40_000,
          maximum_pay: 50_000,
          start_date: '2012-10-05',
          end_date: '2023-10-04',
          locations: [
            'Fulton, MD'
          ],
          url: 'https://www.usajobs.gov/GetJob/ViewDetails/23456'
        )
      end

      before do
        allow(search).to receive(:jobs).and_return jobs_array
      end

      it 'outputs jobs' do
        json = search.to_json
        parsed = JSON.parse(json)
        expect(parsed['jobs'].to_json).to eq(jobs_array.to_json)
      end
    end

    context 'when spelling suggestion is present' do
      before do
        search.instance_variable_set(:@spelling_suggestion, 'spell it this way')
      end

      it 'outputs spelling suggestion' do
        json = search.to_json
        expect(json).to match(/spell it this way/)
      end
    end

    context 'when related search is present' do
      before do
        allow(search).to receive(:related_search).and_return ['also <strong>search</strong> this']
      end

      it 'outputs unhighlighted related search' do
        json = search.to_json
        expect(json).to match(/also search this/)
      end
    end
  end

  describe '#to_xml' do
    let(:affiliate) { affiliates(:non_existent_affiliate) }
    let(:search) { described_class.new(query: 'english', affiliate: affiliate) }

    it 'generates a XML representation of total, start and end records, and search results' do
      search.run
      xml = search.to_xml
      expect(xml).to match(/total/)
      expect(xml).to match(/startrecord/)
      expect(xml).to match(/endrecord/)
      expect(xml).to match(/results/)
    end

    context 'when an error occurs' do
      before do
        search.run
        search.instance_variable_set(:@error_message, 'Some error')
      end

      it 'outputs an error if an error is detected' do
        xml = search.to_xml
        expect(xml).to match(/Some error/)
      end
    end
  end

  describe "helper 'has' methods" do
    let(:search) { described_class.new(query: 'english', affiliate: affiliates(:non_existent_affiliate)) }

    it 'raises an error when no helper can be found' do
      expect { search.not_here }.to raise_error(NoMethodError)
    end
  end

  describe 'has_fresh_news_items?' do
    let(:search) { described_class.new(query: 'english', affiliate: affiliate) }

    context 'when 1 or more news items are less than 6 days old' do
      let(:news_item_results) do
        [mock_model(NewsItem, published_at: DateTime.current.advance(days: 2)),
         mock_model(NewsItem, published_at: DateTime.current.advance(days: 6))]
      end
      let(:news_items) { double('news items', results: news_item_results) }

      before do
        allow(search).to receive(:news_items).and_return(news_items)
        expect(news_items).to receive(:total).and_return(2)
      end

      specify { expect(search).to have_fresh_news_items }
    end

    context 'when all news items are more than 5 days old' do
      let(:news_item_results) do
        [mock_model(NewsItem, published_at: DateTime.current.advance(days: -7)),
         mock_model(NewsItem, published_at: DateTime.current.advance(days: -12))]
      end
      let(:news_items) { double('news items', results: news_item_results) }

      before do
        allow(search).to receive(:news_items).and_return(news_items)
        expect(news_items).to receive(:total).and_return(2)
      end

      specify { expect(search).not_to have_fresh_news_items }
    end
  end
end
