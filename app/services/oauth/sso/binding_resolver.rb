# frozen_string_literal: true

module Oauth
  module Sso
    class BindingResolver
      def self.require_active!(application:, subject:)
        link = OauthPartnerAccountLink.active.find_by(
          oauth_application_id: application.id,
          general_user_id: subject
        )
        if link.blank?
          # Subject may also be partner external_user_id in some integrations.
          link = OauthPartnerAccountLink.active.find_by(
            oauth_application_id: application.id,
            external_user_id: subject
          )
        end

        raise Error.new('BINDING_REQUIRED', 'Active partner binding is required.', http_status: 403) if link.blank?
        raise Error.new('BINDING_INACTIVE', 'Partner binding is inactive.', http_status: 403) unless link.active?

        link
      end
    end
  end
end
