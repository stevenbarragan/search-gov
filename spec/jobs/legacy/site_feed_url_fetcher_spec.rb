require 'spec_helper'

describe SiteFeedUrlFetcher do
  describe '.perform' do
    it 'should import the SiteFeedUrl' do
      site_feed_url = mock_model SiteFeedUrl
      expect(SiteFeedUrl).to receive(:find_by_id).with(100).and_return site_feed_url

      site_feed_url_data = double(SiteFeedUrlData)
      expect(SiteFeedUrlData).to receive(:new).with(site_feed_url).and_return(site_feed_url_data)
      expect(site_feed_url_data).to receive :import
      described_class.perform(100)
    end
  end

  describe '.before_perform_with_timeout' do
    before { @original_timeout = Resque::Plugins::JobTimeout.timeout }
    after { Resque::Plugins::JobTimeout.timeout = @original_timeout }

    it 'sets Resque::Plugins::JobTimeout.timeout to 20 minutes' do
      described_class.before_perform_with_timeout
      expect(Resque::Plugins::JobTimeout.timeout).to eq(20.minutes)
    end
  end
end
