# frozen_string_literal: true

# app/controllers/concerns/authenticatable.rb
module Authenticatable
  extend ActiveSupport::Concern

  def set_authentication_actions(options = {})
    skip_before_action :authenticate, raise: false
    before_action :authenticate, options
  end

  private

  def authenticate
    api_key = request.headers['X-API-KEY']
    return if api_key.present?

    authenticate_user!
  end
end
