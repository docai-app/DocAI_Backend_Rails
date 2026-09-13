# frozen_string_literal: true

# app/controllers/concerns/admin_authenticator.rb
module AdminAuthenticator
  extend ActiveSupport::Concern

  included do
    prepend_before_action :check_admin_token
  end

  private

  def check_admin_token
    expected = ENV['ADMIN_TOKEN'].to_s
    token = request.headers['Authorization'].to_s.match(/\ABearer ([^\s,]+)\z/i)&.captures&.first
    response.headers['Cache-Control'] = 'no-store'
    return if expected.present? && !%w[null undefined].include?(expected) &&
              token.present? && token.bytesize <= 4096 &&
              ActiveSupport::SecurityUtils.secure_compare(token, expected)

    render json: { success: false, error: 'Unauthorized' }, status: :unauthorized
  end
end
