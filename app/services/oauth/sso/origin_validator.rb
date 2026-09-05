# frozen_string_literal: true

module Oauth
  module Sso
    class OriginValidator
      def self.exact_origin?(value)
        uri = URI.parse(value.to_s)
        return false unless uri.is_a?(URI::HTTP) || uri.is_a?(URI::HTTPS)
        return false if uri.host.blank?
        return false if uri.path.present? && uri.path != '/'
        return false if uri.query.present? || uri.fragment.present?
        return false if uri.userinfo.present?

        true
      rescue URI::InvalidURIError
        false
      end

      def self.normalize(value)
        uri = URI.parse(value.to_s)
        origin = "#{uri.scheme}://#{uri.host}"
        default_port = uri.scheme == 'https' ? 443 : 80
        origin += ":#{uri.port}" if uri.port && uri.port != default_port
        origin
      end

      def self.allowed?(application, return_origin)
        origin = normalize(return_origin)
        Array(application.allowed_launch_origins).map { |item| normalize(item) }.include?(origin)
      rescue URI::InvalidURIError
        false
      end
    end
  end
end
