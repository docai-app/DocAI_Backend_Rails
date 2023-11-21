# frozen_string_literal: true

# app/controllers/concerns/authenticatable.rb
module Authenticatable
  extend ActiveSupport::Concern

  def set_authentication_actions(*actions)
    before_action :authenticate, only: actions
  end

  private

  def authenticate
    api_key = request.headers['X-API-KEY']
    return if api_key.present?

    authenticate_user!
  end
end
