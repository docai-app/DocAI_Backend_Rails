# frozen_string_literal: true

class ApiController < ActionController::Base
  before_action :set_paper_trail_whodunnit
  before_action :switch_tenant
  skip_before_action :verify_authenticity_token

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

  rescue_from Exception, with: :render_error

  def switch_tenant
    # Get the subdomain from the referrer
    puts "Original referrer: #{request.referrer}"

    subdomain = Utils.extractReferrerSubdomain(request.referrer)

    puts "Include subdomain? + #{subdomain}"

    # Switch to the tenant, if it exists
    if Apartment.tenant_names.include?(subdomain)
      Apartment::Tenant.switch!(subdomain)
    else
      Apartment::Tenant.switch!('public')
      # render json: { error: "Invalid subdomain" }, status: :unprocessable_entity
    end
  end
end
