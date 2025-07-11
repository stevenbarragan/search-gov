# frozen_string_literal: true

class SearchesController < ApplicationController
  layout :set_layout

  skip_before_action :verify_authenticity_token, :set_default_locale

  before_action :set_affiliate, :set_locale_based_on_affiliate_locale
  #eventually all the searches should be redirected, but currently we're doing it as-needed
  #to ensure that the correct params are being passed, etc.
  before_action :set_web_search_options, :only => [:advanced, :index]
  before_action :set_docs_search_options, :only => :docs
  before_action :set_news_search_options, :only => [:news]
  before_action :force_request_format, :only => [:advanced, :docs, :index, :news]
  after_action :log_search_impression, :only => [:index, :news, :docs]
  include QueryRoutableController

  def index
    if @affiliate.active?
      search_klass, @search_vertical, template = pick_klass_vertical_template
      template = :index_redesign if redesign?
      @search = search_klass.new(@search_options.merge(geoip_info: GeoipLookup.lookup(request.remote_ip)))
      @search.run
      @form_path = search_path
      @page_title = @search.query
      set_search_page_title
      set_search_params
      respond_to do |format|
        format.html { render template }
        format.json { render :json => @search }
      end
    else
      @page_title = "Search Temporarily Unavailable - #{@affiliate.display_name}"
      respond_to do |format|
        format.html { render :inactive_affiliate, layout: 'application' }
        format.json { render json: { error: "This search affiliate has been turned off" }, status: :service_unavailable }
      end
    end
  end

  def docs
    search_klass = docs_search_klass
    @search = search_klass.new(@search_options)
    @search.run
    @form_path = docs_search_path
    @page_title = @search.query
    @search_vertical = :docs
    set_search_page_title
    set_search_params
    template = search_klass == I14ySearch ? :i14y : :docs
    template = :index_redesign if redesign?
    respond_to { |format| format.html { render template } }
  end

  def news
    @search = NewsSearch.new(@search_options)
    @search.run
    @form_path = news_search_path
    set_news_search_page_title
    set_search_page_title
    @search_vertical = :news
    set_search_params
    template = redesign? ? :index_redesign : :news
    respond_to { |format| format.html { render template } }
  end

  def advanced
    @page_title = "#{t(:advanced_search)} - #{@affiliate.display_name}"
    @search = WebSearch.new(@search_options)
    @affiliate = @search_options[:affiliate]
    set_search_params
    permitted_params[:filter] = %w(0 1 2).include?(permitted_params[:filter]) ? permitted_params[:filter] : '1'
    permitted_params[:filetype] = %w(doc pdf ppt txt xls).include?(permitted_params[:filetype]) ? permitted_params[:filetype] : nil
    respond_to { |format| format.html {} }
  end

  private

  def pick_klass_vertical_template
    if get_commercial_results?
      [WebSearch, :web, :index]
    elsif @affiliate.search_elastic_engine?
      [SearchElasticEngine, :SRCH, :i14y]
    elsif gets_i14y_results?
      [I14ySearch, :i14y, :i14y]
    elsif @affiliate.gets_blended_results
      [BlendedSearch, :blended, :blended]
    else
      [WebSearch, :web, :index]
    end
  end

  def set_news_search_page_title
    if permitted_params[:query].present?
      @page_title = permitted_params[:query]
    elsif @search.rss_feed and @search.total > 0
      @page_title = @search.rss_feed.name
    end
  end

  def set_web_search_options
    @search_options = search_options_from_params :filter,
                                                 :since_date,
                                                 :sort_by,
                                                 :tbs,
                                                 :until_date,
                                                 :include_facets
  end

  def set_docs_search_options
    @search_options = search_options_from_params :dc,
                                                 :since_date,
                                                 :sort_by,
                                                 :tbs,
                                                 :until_date
    document_collection = @affiliate.document_collections.find_by_id(@search_options[:dc])
    @search_options.merge!(document_collection: document_collection)
  end

  def set_news_search_options
    @search_options = search_options_from_params :channel,
                                                 :contributor,
                                                 :publisher,
                                                 :since_date,
                                                 :sort_by,
                                                 :subject,
                                                 :tbs,
                                                 :until_date
  end

  def get_commercial_results?
    permitted_params[:cr] == 'true'
  end

  def gets_i14y_results?
    return false if @affiliate.gets_blended_results

    @affiliate.search_gov_engine? ||
      @affiliate.gets_i14y_results ||
      @search_options[:document_collection]&.too_deep_for_bing?
  end

  def log_search_impression
    SearchImpression.log(@search, @search_vertical, permitted_params, request)
  end

  def docs_search_klass
    return I14ySearch if gets_i14y_results?
    return SearchElasticEngine if @affiliate.search_elastic_engine?

    @search_options[:document_collection] ? SiteSearch : WebSearch
  end

  def set_layout
    redesign? ? 'searches_redesign' : 'searches'
  end
end
