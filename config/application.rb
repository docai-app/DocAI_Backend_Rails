# frozen_string_literal: true

require_relative 'boot'

require 'rails/all'
require 'dotenv/load'
require 'apartment/elevators/subdomain'

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module DocaiApi
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 7.0

    config.middleware.use Apartment::Elevators::Subdomain

    # ActionDispatch::Request::Session::DisabledSessionError - Your application has sessions disabled
    config.session_store :cookie_store, key: '_interslice_session'

    # required for session management
    config.middleware.use ActionDispatch::Cookies
    config.middleware.use config.session_store, config.session_options

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    config.time_zone = 'Asia/Taipei'
    config.active_record.default_timezone = :local
    # config.eager_load_paths << Rails.root.join("extras")
    config.eager_load = true
    config.autoloader = :classic

    # Only loads a smaller set of middleware suitable for API only apps.
    # Middleware like session, flash, cookies can be added back manually.
    # Skip views, helpers and assets when generating a new resource.
    config.api_only = false

    config.active_job.queue_adapter = :sidekiq

    Redis.exists_returns_integer = true

    config.hosts << 'docai-dev.m2mda.com'
    config.hosts << 'docai.m2mda.com'
    config.hosts << 'ab7b-27-109-208-108.ngrok-free.app'
    config.hosts << '5xwqlf0q-3001.asse.devtunnels.ms'
    config.hosts << '2396-27-109-208-108.ngrok-free.app'

    config.action_cable.mount_path = '/cable'
  end
end
