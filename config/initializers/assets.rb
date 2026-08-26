# frozen_string_literal: true

# Doorkeeper authorization/consent UI styles (see app/assets/config/manifest.js).
Rails.application.config.assets.precompile += %w[
  doorkeeper/application.css
]
