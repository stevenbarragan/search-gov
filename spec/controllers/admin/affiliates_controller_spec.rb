# frozen_string_literal: true

describe Admin::AffiliatesController do
  fixtures :users, :affiliates, :memberships, :languages
  let(:config) { described_class.active_scaffold_config }

  context 'when logged in as a non-affiliate admin user' do
    before do
      activate_authlogic
      UserSession.create(users('non_affiliate_admin'))
    end

    it 'redirects to the usasearch home page' do
      get :index
      expect(response).to redirect_to(account_path)
    end
  end

  context 'when not logged in' do
    it 'redirects to the login page' do
      get :index
      expect(response).to redirect_to(login_path)
    end
  end

  describe '#analytics' do
    context 'when logged in as an affiliate admin' do
      let(:affiliate) { affiliates('basic_affiliate') }

      before do
        activate_authlogic
        UserSession.create(users('affiliate_admin'))
      end

      it 'redirects to the affiliate analytics page for the affiliate id passed' do
        get :analytics, params: { id: affiliate.id }
        expect(response).to redirect_to new_site_queries_path(affiliate)
      end
    end
  end

  describe '#edit' do
    context 'when logged in as an affiliate admin' do
      render_views
      let(:affiliate) { affiliates('basic_affiliate') }

      before do
        activate_authlogic
        UserSession.create(users('affiliate_admin'))
        get :edit, params: { id: affiliate.id }
      end

      it { is_expected.to respond_with :success }
    end
  end

  describe '#update' do
    let(:affiliate) { affiliates(:basic_affiliate) }

    before do
      activate_authlogic
      UserSession.create(users(:affiliate_admin))
    end

    context 'when configuring Active Scaffold' do
      let(:update_columns) { config.update.columns }

      describe 'subgroups' do
        it 'contains the specified subgroups' do
          expect(update_columns.map(&:label)).to contain_exactly('Settings', 'Enable/disable Settings', 'Display Settings', 'Analytics-Tracking Code')
        end
      end

      describe 'Settings subgroup' do
        let(:settings_columns) do
          %i[ active agency display_name domain_control_validation_code
              fetch_concurrency ga_web_property_id i14y_date_stamp_enabled locale name
              search_engine website affiliate_feature_addition excluded_domains i14y_memberships ]
        end

        it 'contains the specified columns' do
          expect(update_columns.find { |c| c.label == 'Settings' }.to_a).to match_array(settings_columns)
        end
      end

      describe "'Enable/disable Settings' subgroup" do
        let(:enable_disable_columns) do
          %i[ dap_enabled gets_blended_results gets_commercial_results_on_blended_search
              gets_i14y_results is_federal_register_document_govbox_enabled gets_results_from_all_domains
              is_medline_govbox_enabled is_photo_govbox_enabled is_related_searches_enabled
              is_rss_govbox_enabled is_sayt_enabled is_video_govbox_enabled jobs_enabled raw_log_access_enabled ]
        end

        it 'contains the specified columns' do
          expect(update_columns.find { |c| c.label == 'Enable/disable Settings' }.to_a).to match_array(enable_disable_columns)
        end
      end

      describe 'Display Settings subgroup' do
        let(:display_columns) do
          %i[ use_redesigned_results_page footer_fragment header_tagline_font_family
              header_tagline_font_size header_tagline_font_style no_results_pointer
              page_one_more_results_pointer navigation_dropdown_label related_sites_dropdown_label
              looking_for_government_services show_search_filter_settings ]
        end

        it 'contains the specified columns' do
          expect(update_columns.find { |c| c.label == 'Display Settings' }.to_a).to match_array(display_columns)
        end
      end

      describe 'Analytics-Tracking Code subgroup' do
        let(:analytics_columns) do
          %i[ga_web_property_id domain_control_validation_code external_tracking_code submitted_external_tracking_code]
        end

        it 'contains the specified columns' do
          expect(update_columns.find { |c| c.label == 'Analytics-Tracking Code' }.to_a).to match_array(analytics_columns)
        end
      end
    end
  end

  describe '#export' do
    let(:affiliate) { affiliates(:basic_affiliate) }

    before do
      activate_authlogic
      UserSession.create(users(:affiliate_admin))
    end

    context 'when configuring Active Scaffold' do
      let(:export_columns) do
        %i[ active
            agency
            api_access_key
            created_at
            dap_enabled
            display_name
            display_logo_only
            domain_control_validation_code
            external_tracking_code
            favicon_url
            features
            fetch_concurrency
            footer_fragment
            ga_web_property_id
            gets_blended_results
            gets_commercial_results_on_blended_search
            gets_i14y_results
            gets_results_from_all_domains
            header_tagline_font_family
            header_tagline_font_size
            header_tagline_font_style
            i14y_date_stamp_enabled
            id
            is_federal_register_document_govbox_enabled
            is_medline_govbox_enabled
            is_photo_govbox_enabled
            is_related_searches_enabled
            is_rss_govbox_enabled
            is_sayt_enabled
            is_video_govbox_enabled
            jobs_enabled
            last_month_query_count
            locale
            looking_for_government_services
            mobile_logo_url
            name
            raw_log_access_enabled
            recent_user_activity
            related_sites_dropdown_label
            search_engine
            show_search_filter_settings
            show_vote_org_link
            site_domains
            submitted_external_tracking_code
            theme
            updated_at
            use_redesigned_results_page
            website ]
      end

      describe 'exports file' do
        before { post :export, params: { format: :csv } }

        it { is_expected.to respond_with :success }
      end

      describe 'columns' do
        it 'contains the specified columns' do
          expect(config.export.columns.to_a).to match_array(export_columns)
        end
      end
    end
  end
end
