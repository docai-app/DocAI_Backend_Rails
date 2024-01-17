# frozen_string_literal: true

# app/controllers/concerns/admin_authenticator.rb
module AdminAuthenticator
  extend ActiveSupport::Concern

  included do
    before_action :check_admin_token
  end

  private

  def check_admin_token
    authenticate_or_request_with_http_token do |token, _options|
      ActiveSupport::SecurityUtils.secure_compare(token, ENV['ADMIN_TOKEN'])
    end
  end
end
