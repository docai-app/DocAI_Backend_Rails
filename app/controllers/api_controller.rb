# frozen_string_literal: true

class ApiController < ActionController::Base
  before_action :switch_tenant
  before_action :set_paper_trail_whodunnit
  skip_before_action :verify_authenticity_token
  respond_to :json

  # 我平時係呢句
  # protect_from_forgery with: :null_session

  # def require_admin
  #   return current_user.has_role? :admin

  #   return :user_not_authorized
  # end

  def render_error(exception = nil)
    @status_code = params[:code] || 400 # ActionDispatch::ExceptionWrapper.new(env, exception).status_code
    render json: { success: false, error: exception.message, status: @status_code }
  end

  def render_error_msg(msg, code = nil)
    status = code || 400
    render json: { success: false, error: msg, status: }
  end

  def json_success(data = nil)
    render json: { success: true, doc: data }.compact
  end

  def json_fail(msg)
    render json: { success: false, error: msg }.compact
  end

  def user_not_authorized
    json_fail('You are not authorized to perform this action.')
  end

  def switch_tenant
    # Get the subdomain from the auth jwt token or referrer
    puts 'API controller working............'
    if request.headers['Authorization'].present?
      tenant_name = Utils.extractRequestTenantByToken(request)
    elsif request.headers['X-API-KEY'].present?
      key = request.headers['X-API-KEY']
      api_key = ApiKey.active.find_by(key:)
      tenant_name = api_key.tenant
      Apartment::Tenant.switch!(tenant_name)
      @current_user = api_key.user
    else
      tenant_name = Utils.extractReferrerSubdomain(request.referrer)
    end
    puts "tenantName: #{tenant_name}"
    Apartment::Tenant.switch!(tenant_name)
  end

  rescue_from Exception, with: :render_error
end
