# frozen_string_literal: true

class AdminApiController < ActionController::Base
  before_action :set_paper_trail_whodunnit, :switch_public_tenant # 切換到公共租戶
  skip_before_action :verify_authenticity_token
  respond_to :json

  # 我平時係呢句
  # protect_from_forgery with: :null_session

  # def require_admin
  #   return current_user.has_role? :admin

  #   return :user_not_authorized
  # end

  def switch_public_tenant
    Apartment::Tenant.switch!('public')
  end

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
end
