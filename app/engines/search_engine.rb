class SearchEngine
  class SearchError < RuntimeError;
  end

  DEFAULT_OFFSET = 0
  DEFAULT_PER_PAGE = 10
  MAX_ATTEMPT_COUNT = 2

  class_attribute :api_endpoint, instance_writer: false

  attr_reader :start_time,
              :cached_response

  attr_accessor :query,
                :offset,
                :per_page,
                :filter_level,
                :api_connection,
                :enable_highlighting

  def initialize(options = {})
    @query = options[:query]
    @per_page = options[:per_page] || DEFAULT_PER_PAGE
    @offset = options[:offset] || DEFAULT_OFFSET
    @enable_highlighting = options[:enable_highlighting].nil? || options[:enable_highlighting]
    yield self if block_given?
  end

  def execute_query
    http_params = params
    Rails.logger.debug "#{self.class.name} Url: #{api_endpoint}\nParams: #{http_params}"
    retry_block(attempts: MAX_ATTEMPT_COUNT, catch: [Faraday::TimeoutError, Faraday::ConnectionFailed]) do |attempt|
      reset_timer
      @cached_response = api_connection.get(api_endpoint, http_params)
      process_cached_response(attempt)
    end
  rescue => error
    raise SearchError.new(error)
  end

  protected

  def from_cache
    false
  end

  def reset_timer
    @start_time = now
  end

  def now
    Time.now.to_f
  end

  def elapsed_ms
    ((now - start_time) * 1000).to_i
  end

  def process_cached_response(attempt)
    response = parse_search_engine_response(cached_response)
    result_count = response.results.size
    retry_count = attempt - 1

    response.diagnostics = {
      result_count: result_count,
      from_cache: from_cache ? 'none' : true,
      retry_count: retry_count,
      elapsed_time_ms: elapsed_ms,
      tracking_information: response.tracking_information,
    }

    response
  end

  def get_filter_index(filter_param_str)
    idx= (filter_param_str.present? && filter_param_str.to_s.match(/\d/)) ? filter_param_str.to_i : 1
    (0..2).include?(idx) ? idx : 1
  end

  def spelling_results(suggestion)
    return nil if suggestion.blank?
    spelling_suggestion = SpellingSuggestion.new(query, suggestion)
    spelling_suggestion.cleaned
  end

  private

  def engine_tag_value
    self.class.name.split('::').last.underscore
  end
end
