# frozen_string_literal: true

require 'rack/auth/basic'
require 'digest'

# Wrap only Sidekiq Web, not Redis, workers or business API routes.
# Leave Sidekiq's session/CSRF middleware intact. Missing configuration denies access.
class AdminSidekiqAuthentication
  def initialize(app)
    @guard = Rack::Auth::Basic.new(app, 'Sidekiq Administration') do |user, password|
      expected_user = ENV['SIDEKIQ_ADMIN_USER'].to_s
      expected_password = ENV['SIDEKIQ_ADMIN_PASSWORD'].to_s
      expected_user.present? && expected_password.present? &&
        (ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(user), Digest::SHA256.hexdigest(expected_user)) &
         ActiveSupport::SecurityUtils.secure_compare(Digest::SHA256.hexdigest(password), Digest::SHA256.hexdigest(expected_password)))
    end
  end

  def call(env)
    env['warden']&.custom_failure!
    status, headers, body = @guard.call(env)
    [status, headers.merge('Cache-Control' => 'no-store'), body]
  end
end
