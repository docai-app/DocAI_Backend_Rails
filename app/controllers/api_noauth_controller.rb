# frozen_string_literal: true

class ApiNoauthController < ActionController::Base
  before_action :set_paper_trail_whodunnit
  skip_before_action :verify_authenticity_token

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
