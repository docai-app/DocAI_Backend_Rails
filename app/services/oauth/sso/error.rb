# frozen_string_literal: true

module Oauth
  module Sso
    class Error < StandardError
      attr_reader :code, :http_status

      def initialize(code, message, http_status:)
        super(message)
        @code = code
        @http_status = http_status
      end
    end
  end
end
