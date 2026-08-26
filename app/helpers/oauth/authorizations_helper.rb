# frozen_string_literal: true

module Oauth
  module AuthorizationsHelper
    IDP_NAME = 'AIEnglish'

    def oauth_client_record
      return @oauth_client_record if defined?(@oauth_client_record)

      client = @pre_auth&.client
      @oauth_client_record =
        if client.is_a?(OauthApplication)
          client
        elsif client
          OauthApplication.find_by(uid: client.uid) || OauthApplication.find_by(id: client.id)
        end
    end

    def oauth_client_name
      oauth_client_record&.name || @pre_auth.client.name
    end

    def oauth_client_logo_url
      oauth_client_record&.logo_url.presence
    end

    def oauth_client_homepage_url
      oauth_client_record&.homepage_url.presence
    end

    def oauth_client_privacy_url
      oauth_client_record&.privacy_policy_url.presence
    end

    def oauth_client_tos_url
      oauth_client_record&.tos_url.presence
    end

    def oauth_user
      resource_owner if respond_to?(:resource_owner)
    end

    def oauth_user_display_name
      user = oauth_user
      return I18n.t('doorkeeper.authorizations.new.default_user') unless user

      user.try(:nickname).presence || user.try(:email) || IDP_NAME
    end

    def oauth_user_email
      oauth_user&.try(:email)
    end

    def oauth_user_initial
      oauth_user_display_name.to_s.strip.first&.upcase || 'A'
    end

    def oauth_scope_description(scope)
      I18n.t(scope, scope: %i[doorkeeper scopes], default: scope.to_s.humanize)
    end

    def oauth_scope_icon(scope)
      {
        'openid' => 'shield',
        'profile' => 'user',
        'email' => 'mail',
        'offline_access' => 'refresh'
      }[scope.to_s] || 'check'
    end
  end
end
