# frozen_string_literal: true

module Oauth
  module Sso
    class EmbedSessionResolver
      def self.resolve(request)
        raw = EmbedCookie.read(request)
        return nil if raw.blank?

        parsed = EmbedCookie.parse(raw)
        return nil if parsed.blank?

        session = OauthEmbedSession.find_by(id: parsed[:session_id])
        return nil if session.blank? || !session.active?

        digest = TokenDigest.sha256_hex(parsed[:secret])
        return nil unless TokenDigest.secure_compare(digest, session.session_secret_digest)

        session.touch_seen!
        session
      end
    end
  end
end
