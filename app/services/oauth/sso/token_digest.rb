# frozen_string_literal: true

module Oauth
  module Sso
    module TokenDigest
      module_function

      def sha256_hex(value)
        OpenSSL::Digest::SHA256.hexdigest(value.to_s)
      end

      def secure_compare(a, b)
        return false if a.blank? || b.blank? || a.bytesize != b.bytesize

        ActiveSupport::SecurityUtils.secure_compare(a, b)
      end
    end
  end
end
