# frozen_string_literal: true

module Oauth
  module Sso
    class ClientAuthenticator
      def self.authenticate!(request)
        header = request.headers['Authorization'].to_s
        unless header.start_with?('Basic ')
          raise Error.new('INVALID_CLIENT', 'Confidential client authentication is required.', http_status: 401)
        end

        decoded = Base64.decode64(header.delete_prefix('Basic ').strip)
        client_id, client_secret = decoded.split(':', 2)
        if client_id.blank? || client_secret.blank?
          raise Error.new('INVALID_CLIENT', 'Confidential client authentication is required.', http_status: 401)
        end

        application = OauthApplication.find_by(uid: client_id)
        unless application&.enabled? && application.sso_launch_allowed?
          raise Error.new('INVALID_CLIENT', 'Client is not allowed to use SSO launch.', http_status: 401)
        end

        unless secret_matches?(application, client_secret)
          raise Error.new('INVALID_CLIENT', 'Invalid client credentials.', http_status: 401)
        end

        application
      rescue ArgumentError
        raise Error.new('INVALID_CLIENT', 'Invalid client credentials.', http_status: 401)
      end

      def self.secret_matches?(application, client_secret)
        if application.respond_to?(:secret_matches?)
          application.secret_matches?(client_secret)
        elsif application.respond_to?(:valid_secret?)
          application.valid_secret?(client_secret)
        else
          ActiveSupport::SecurityUtils.secure_compare(application.secret.to_s, client_secret.to_s)
        end
      end
    end
  end
end
