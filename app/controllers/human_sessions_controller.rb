class HumanSessionsController < ApplicationController
  BOT_OR_NOT_SECRET = File.read("#{Rails.root}/config/bot_or_not_secret.txt")

  layout false
  before_action :set_affiliate, only: :new
  before_action :set_locale_based_on_affiliate_locale, only: :new
  skip_before_action :verify_authenticity_token

  def new
    @redirect_to = CGI::escape(params[:r])
  end

  def create
    if verify_recaptcha
      timestamp = Time.now.to_i
      digest = Digest::SHA256.hexdigest("#{client_ip}:#{timestamp}:#{secret}")
      cookies[:bon] = "#{client_ip}:#{timestamp}:#{digest}"
    end

    redirect_to(redirect_destination, allow_other_host: true)
  end

  private

  def client_ip
    request.remote_ip
  end

  def redirect_destination
    destination = CGI::unescape(params['redirect_to'])
    destination.start_with?('/') ? destination : PAGE_NOT_FOUND
  end

  def secret
    BOT_OR_NOT_SECRET
  end

  def set_affiliate
    redirect_to_query_string = params[:r].sub(%r{^.*\?}, '')
    redirect_to_params = Rack::Utils.parse_nested_query(redirect_to_query_string)
    @affiliate = Affiliate.find_by_name(redirect_to_params['affiliate'])
    redirect_unless_affiliate
  end
end
