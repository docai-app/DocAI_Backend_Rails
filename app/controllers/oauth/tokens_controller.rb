# frozen_string_literal: true

module Oauth
  # Token endpoint inherits Doorkeeper behavior.
  # Disabled clients are rejected via allow_grant_flow_for_client in initializer.
  class TokensController < Doorkeeper::TokensController
  end
end
