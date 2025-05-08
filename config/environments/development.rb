# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.after_initialize do
    Bullet.enable = true
    Bullet.alert = true
    Bullet.bullet_logger = true
    Bullet.console = true
    Bullet.rails_logger = true
    Bullet.add_footer = true
  end

  # Settings specified here will take precedence over those in config/application.rb.

  # In the development environment your application's code is reloaded any time
  # it changes. This slows down response time but is perfect for development
  # since you don't have to restart the web server when you make code changes.
  config.cache_classes = false

  # Do not eager load code on boot.
  config.eager_load = false

  # Show full error reports.
  config.consider_all_requests_local = true

  # Enable server timing
  config.server_timing = true

  # Enable/disable caching. By default caching is disabled.
  # Run rails dev:cache to toggle caching.
  if Rails.root.join('tmp/caching-dev.txt').exist?
    config.cache_store = :memory_store
    config.public_file_server.headers = {
      'Cache-Control' => "public, max-age=#{2.days.to_i}"
    }
  else
    config.action_controller.perform_caching = false

    config.cache_store = :null_store
  end

  # Store uploaded files on the local file system (see config/storage.yml for options).
  config.active_storage.service = :microsoft

  # Don't care if the mailer can't send.
  config.action_mailer.raise_delivery_errors = false

  config.action_mailer.perform_caching = false

  # Print deprecation notices to the Rails logger.
  config.active_support.deprecation = :log

  # Raise exceptions for disallowed deprecations.
  config.active_support.disallowed_deprecation = :raise

  # Tell Active Support which deprecation messages to disallow.
  config.active_support.disallowed_deprecation_warnings = []

  # Raise an error on page load if there are pending migrations.
  config.active_record.migration_error = :page_load

  # Highlight code that triggered database queries in logs.
  config.active_record.verbose_query_logs = true

  # Raises error for missing translations.
  # config.i18n.raise_on_missing_translations = true

  # Annotate rendered view with file names.
  # config.action_view.annotate_rendered_view_with_filenames = true

  # Uncomment if you wish to allow Action Cable access from any origin.
  config.action_cable.disable_request_forgery_protection = true
  config.action_cable.url = ENV.fetch('ACTION_CABLE_URL', 'wss://docai-dev.m2mda.com/cable')
  # config.action_cable.mount_path = nil
  # config.action_cable.url = ['ws://localhost:3000/cable', 'wss://localhost:3000/cable', 'ws://localhost:3010/cable', 'wss://localhost:3010/cable',
  #                            'ws://docai-dev.m2mda.com/cable', 'wss://docai-dev.m2mda.com/cable', 'ws://chatbot-dev.docai.net/cable', 'wss://chatbot-dev.docai.net/cable', 'ws://dev-docai-chatbot-plus.vercel.app/cable', 'wss://dev-docai-chatbot-plus.vercel.app/cable']
  # config.action_cable.allowed_request_origins = ['http://localhost:3000', 'https://localhost:3000',
  #                                                'http://docai-dev.m2mda.com', 'https://docai-dev.m2mda.com', 'http://chatbot-dev.docai.net', 'https://chatbot-dev.docai.net', 'http://dev-docai-chatbot-plus.vercel.app', 'https://dev-docai-chatbot-plus.vercel.app']

  config.active_storage.service = :microsoft

  config.autoloader = :classic

  config.active_job.queue_adapter = :sidekiq

  config.time_zone = 'Asia/Taipei'

  # Redis.exists_returns_integer = true

  # Gmail SMTP configuration
  config.action_mailer.delivery_method = :smtp
  config.action_mailer.smtp_settings = {
    address: ENV.fetch('SMTP_ADDRESS', 'smtp.gmail.com'),
    port: ENV.fetch('SMTP_PORT', 587),
    domain: ENV.fetch('SMTP_DOMAIN', 'gmail.com'), # 您的域名，或者gmail.com
    user_name: ENV.fetch('SMTP_USERNAME'),
    password: ENV.fetch('SMTP_PASSWORD'),
    authentication: ENV.fetch('SMTP_AUTHENTICATION', 'plain'), # 'plain', 'login', 'cram_md5'
    enable_starttls_auto: ActiveModel::Type::Boolean.new.cast(ENV.fetch('SMTP_ENABLE_STARTTLS_AUTO', true)), # 確保是布爾值
    openssl_verify_mode: 'peer' # 對於Gmail和許多現代SMTP服務器，推薦設置
  }

  # 確保在開發中能看到郵件發送錯誤
  config.action_mailer.raise_delivery_errors = true
  # 預覽郵件 (可選，但推薦在開發中使用)
  config.action_mailer.show_previews = true

  # 設置默認的URL選項，這對於郵件中的連結生成很重要
  config.action_mailer.default_url_options = { host: ENV.fetch('MAILER_DEFAULT_HOST', 'localhost'),
                                               port: ENV.fetch('MAILER_DEFAULT_PORT', 3000) }

  # 設置默認的發件人地址 (也可以在 ApplicationMailer 中設置)
  # ActionMailer::Base.default from: ENV.fetch('MAILER_SENDER', '"AI English Support" <aienglish-support@docai.net>')
  # 或者在 ApplicationMailer 中設置:
  # class ApplicationMailer < ActionMailer::Base
  #   default from: ENV.fetch('MAILER_SENDER', '"AI English Support" <aienglish-support@docai.net>')
  #   layout "mailer"
  # end
end
