# frozen_string_literal: true

module ReactHelper
  def search_results_layout(search, params, vertical, affiliate, search_options)
    data = {
      additionalResults: govbox_set_data(search),
      affiliate: affiliate_data(affiliate),
      agencyName: agency_name(affiliate.agency),
      alert: search_page_alert(affiliate.alert),
      extendedHeader: affiliate.use_extended_header,
      facetsEnabled: ENV.fetch('FACETED_SEARCH_ENABLED', 'false') == 'true',
      fontsAndColors: affiliate.visual_design_json,
      footerLinks: links(affiliate, :footer_links),
      identifierContent: identifier_content(affiliate),
      identifierLinks: links(affiliate, :identifier_links),
      jobsEnabled: (affiliate.jobs_enabled? and search.modules.include?('JOBS')),
      language: affiliate.language.slice(:code, :rtl),
      navigationLinks: navigation_links(search, params),
      newsLabel: news_label(search),
      noResultsMessage: no_result_message(search),
      page: page_data(affiliate),
      params:,
      primaryHeaderLinks: links(affiliate, :primary_header_links),
      relatedSearches: related_searches(search),
      relatedSites: related_sites(search),
      relatedSitesDropdownLabel: affiliate.related_sites_dropdown_label,
      resultsData: results_data(search),
      secondaryHeaderLinks: links(affiliate, :secondary_header_links),
      sitelimit: sitelimit_alert(search, params),
      spellingSuggestion: spelling_text(search, search_options),
      translations: translations(affiliate.locale),
      vertical:
    }

    react_component('SearchResultsLayout', data.compact_blank)
  end

  def affiliate_data(affiliate)
    affiliate.slice(:id, :name)
  end

  def page_data(affiliate)
    {
      affiliate: affiliate.name,
      display_logo_only: affiliate.display_logo_only,
      showVoteOrgLink: affiliate.show_vote_org_link && ENV.fetch('ENABLE_VOTE_ORG_LINK'),
      title: affiliate.display_name,
      logo: {
        text: logo_text(affiliate.header_logo_blob),
        url: header_logo_url(affiliate.header_logo)
      },
      homepageUrl: affiliate.website
    }
  end

  def header_logo_url(header_logo)
    return if header_logo.blank?

    url_for(header_logo)
  end

  def logo_text(blob)
    return unless blob&.custom_metadata

    blob.custom_metadata[:alt_text]
  end

  private

  def related_searches(search)
    return [] if search.is_a?(NewsSearch) || search.related_search.nil?

    search.related_search.map do |related_term|
      {
        label: related_term,
        link: search_path(affiliate: search.affiliate.name, query: strip_tags(related_term))
      }
    end
  end

  def news_label(search)
    return if search.query.blank? || search.is_a?(NewsSearch)

    affiliate = search.affiliate
    {
      newsAboutQuery: news_about_query(affiliate, search.query),
      results: news_items_results(affiliate, search)
    }
  end

  def sitelimit_alert(search, params)
    return unless params[:sitelimit]

    {
      sitelimit: params[:sitelimit],
      url: search_path(affiliate: search.affiliate.name, query: search.query)
    }
  end

  def spelling_text(search, search_options)
    return if search.spelling_suggestion.blank?

    spelling_suggestion_links(search, search_options) do |suggested_query, suggested_url, original_url|
      {
        suggested: link_to(suggested_query, suggested_url, class: 'suggestedQuery'),
        original: link_to(search.query, original_url, class: 'originalQuery'),
        originalUrl: original_url,
        originalQuery: search.query,
        suggestedQuery: suggested_query,
        suggestedUrl: suggested_url
      }
    end
  end

  def no_result_message(search)
    return unless search.results.blank? && search.query.present?

    search.affiliate.no_results_error
  end

  def translations(locale)
    I18n.backend.translations.slice(:en, locale.to_sym)
  end

  def search_page_alert(alert)
    return unless alert&.renderable?

    alert.slice('text', 'title')
  end

  def related_sites(search)
    connections = search.affiliate.connections
    connections.map do |connection|
      {
        label: connection.label,
        link: search_url(affiliate: connection.connected_affiliate.name, query: search.query)
      }
    end
  end

  def links(affiliate, type)
    links = affiliate.send(type)

    links.map do |link|
      {
        title: link.title,
        url: link.url
      }
    end
  end

  def default_tab(search, params)
    {
      active: is_default_search?(search),
      facet: 'Default',
      label: search.affiliate.default_search_label,
      url: search_path(params.slice(:affiliate, :m).merge(query: search.query))
    }
  end

  def navigation_links(search, search_params)
    non_default_search_navigable = detect_non_default_search_navigable(search)

    [default_tab(search, search_params)] + renderable_navigations(search).map do |navigation|
      navigable = navigation.navigable

      {
        active: non_default_search_navigable == navigable,
        facet: navigation.navigable_facet_type,
        label: navigable.name,
        url: navigable_path(navigable, search, search_params)
      }
    end
  end

  def identifier_content(affiliate)
    {
      domainName: affiliate.identifier_domain_name,
      parentAgencyName: affiliate.parent_agency_name,
      parentAgencyLink: affiliate.parent_agency_link,
      logoUrl: identifier_logo_url(affiliate.identifier_logo),
      logoAltText: logo_text(affiliate.identifier_logo_blob),
      lookingForGovernmentServices: affiliate.looking_for_government_services
    }
  end

  def identifier_logo_url(identifier_logo)
    return if identifier_logo.blank?

    url_for(identifier_logo)
  end

  def agency_name(agency)
    return if agency.nil?

    agency.abbreviation || agency.name
  end

  def govbox_set_data(search)
    return if search.govbox_set.nil?

    affiliate = search.affiliate
    govbox_set_json = search.govbox_set.as_json
    if show_results_format?(affiliate) && !affiliate.display_created_date_on_search_results?
      reject_keys_from_hash(govbox_set_json[:federalRegisterDocuments], 'publication_date') if govbox_set_json[:federalRegisterDocuments].present?
      reject_keys_from_hash(govbox_set_json[:newsItems], 'published_at') if govbox_set_json[:newsItems].present?
    end
    govbox_set_json
  end

  def reject_keys_from_hash(results, key)
    return if results.blank?

    results.map do |result|
      result.delete(key)
    end
  end

  def results_data(search)
    return if search.normalized_results.nil?

    affiliate = search.affiliate
    if show_results_format?(affiliate)
      show_results_content(affiliate, boolean_keys = [])
      search.normalized_results[:results].each do |result|
        result.reject! { |k| boolean_keys.include?(k) }
      end
    end
    search.normalized_results
  end

  def show_results_content(affiliate, boolean_keys)
    boolean_keys << :thumbnailUrl unless affiliate.display_image_on_search_results?
    boolean_keys << :fileType unless affiliate.display_filetype_on_search_results?
    boolean_keys << :publishedAt << :publishedDate unless affiliate.display_created_date_on_search_results?
    boolean_keys << :updatedDate unless affiliate.display_updated_date_on_search_results?
  end
end
