# frozen_string_literal: true

class WebResultsPostProcessor < ResultsPostProcessor
  include ResultsRejector
  SPECIAL_URL_PATH_EXT_NAMES = %w[doc pdf ppt ps rtf swf txt xls docx pptx xlsx].freeze

  attr_reader :results

  def initialize(query, affiliate, results)
    super
    @affiliate = affiliate
    @results = results
    @news_item_hash = @affiliate.rss_feeds.non_managed.present? ? build_news_item_hash_from_search(query) : {}
    @link_hash = title_description_date_hash_by_link
    @excluded_urls = @affiliate.excluded_urls_set
  end

  def post_processed_results
    reject_excluded_urls(link_field: :unescaped_url)

    post_processed = @results.collect do |result|
      title, content = title_content_from_news_item(result.unescaped_url, @link_hash)
      title ||= result.title
      content ||= result.content
      { 'title' => title,
        'content' => content,
        'unescapedUrl' => result.unescaped_url,
        'publishedAt' => (@link_hash[result.unescaped_url].published_at rescue nil) }
    end
    post_processed.compact
  end

  def normalized_results(total_results)
    {
      results: format_results,
      total: @affiliate.bing_v7_engine? ? nil : total_results,
      totalPages: total_pages(total_results),
      unboundedResults: @affiliate.bing_v7_engine?
    }
  end

  private

  def format_results
    @results.map do |result|
      {
        title: translate_highlights(result['title']),
        url: result['unescaped_url'],
        fileType: file_type(result['unescaped_url']),
        description: truncate_description(translate_highlights(result['content']))
      }.compact
    end
  end

  def title_description_date_hash_by_link
    links_news_items = NewsItem.select([:link, :title, :description, :published_at]).
      where(rss_feed_url_id: @affiliate.rss_feed_urls.pluck(:id), link: @results.collect(&:unescaped_url)).
      map { |news_item| [news_item.link, news_item] }
    Hash[links_news_items]
  end

  def title_content_from_news_item(result_url, link_hash)
    news_item = @news_item_hash[result_url] || link_hash[result_url]
    [news_item.title, news_item.description] if news_item
  end

  def build_news_item_hash_from_search(query)
    news_search = ElasticNewsItem.search_for(q: query,
                                             rss_feeds: @affiliate.rss_feeds,
                                             excluded_urls: @affiliate.excluded_urls,
                                             language: @affiliate.indexing_locale,
                                             sort: "",
                                             size: NewsSearch::DEFAULT_VIDEO_PER_PAGE)
    Hash[news_search.results.collect { |news_item| [news_item.link, news_item] }]
  end

  def file_type(url)
    return if url.blank?

    ext_name = File.extname(url)[1..]
    ext_name.upcase if SPECIAL_URL_PATH_EXT_NAMES.include?(ext_name&.downcase)
  end
end
