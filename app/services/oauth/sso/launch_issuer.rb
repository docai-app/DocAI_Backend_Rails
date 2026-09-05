# frozen_string_literal: true

module Oauth
  module Sso
    class LaunchIssuer
      TTL_SECONDS = Integer(ENV.fetch('OAUTH_SSO_LAUNCH_TTL_SECONDS', '60'))
      MAX_TTL_SECONDS = 120

      def initialize(application:, input:, request_id:)
        @application = application
        @input = input
        @request_id = request_id
      end

      def call
        validate_input!
        assert_origin!
        binding = BindingResolver.require_active!(application: @application, subject: @input[:subject])
        assignment = AssignmentAccess.find_assignment!(@input[:assignment_id])
        AssignmentAccess.assert_can_open!(user: binding.general_user, assignment: assignment)

        create_or_reuse_launch!(binding: binding, assignment: assignment)
      end

      private

      def validate_input!
        subject = @input[:subject].to_s.strip
        assignment_id = @input[:assignment_id].to_s.strip
        mode = @input[:mode].to_s.strip
        return_origin = @input[:return_origin].to_s.strip
        nonce = @input[:nonce].to_s.strip

        if subject.blank? || assignment_id.blank? || mode.blank? || return_origin.blank? || nonce.blank?
          raise Error.new('INVALID_REQUEST', 'Missing required launch fields.', http_status: 400)
        end
        unless OauthEmbedLaunch::MODES.include?(mode)
          raise Error.new('INVALID_REQUEST', 'mode must be embedded or new_tab.', http_status: 400)
        end
        unless OriginValidator.exact_origin?(return_origin)
          raise Error.new('INVALID_RETURN_ORIGIN', 'returnOrigin must be an exact origin.', http_status: 400)
        end
        if nonce.bytesize < 16
          raise Error.new('INVALID_REQUEST', 'nonce must be at least 128-bit entropy.', http_status: 400)
        end

        @input = {
          subject: subject,
          assignment_id: assignment_id,
          mode: mode,
          return_origin: OriginValidator.normalize(return_origin),
          nonce: nonce
        }
      end

      def assert_origin!
        return if OriginValidator.allowed?(@application, @input[:return_origin])

        raise Error.new('INVALID_RETURN_ORIGIN', 'returnOrigin is not registered for this client.', http_status: 400)
      end

      def create_or_reuse_launch!(binding:, assignment:)
        existing = OauthEmbedLaunch.find_by(client_id: @application.uid, nonce: @input[:nonce])
        return rebuild_response(existing) if existing

        launch_id = SecureRandom.uuid
        key_version = TicketCrypto::ACTIVE_KEY_VERSION
        secret = TicketCrypto.derive_secret(
          client_id: @application.uid,
          nonce: @input[:nonce],
          launch_id: launch_id,
          key_version: key_version
        )
        ttl = [[TTL_SECONDS, 1].max, MAX_TTL_SECONDS].min

        launch = OauthEmbedLaunch.create!(
          id: launch_id,
          client_id: @application.uid,
          subject: binding.general_user_id.to_s,
          assignment_id: assignment.id,
          mode: @input[:mode],
          return_origin: @input[:return_origin],
          nonce: @input[:nonce],
          request_id: @request_id,
          ticket_secret_digest: TokenDigest.sha256_hex(secret),
          key_version: key_version,
          expires_at: ttl.seconds.from_now,
          meta: {
            requested_subject: @input[:subject],
            binding_id: binding.id
          }
        )

        build_response(launch, secret)
      rescue ActiveRecord::RecordNotUnique
        existing = OauthEmbedLaunch.find_by!(client_id: @application.uid, nonce: @input[:nonce])
        rebuild_response(existing)
      end

      def rebuild_response(launch)
        assert_idempotent_payload!(launch)
        unless launch.active?
          raise Error.new('IDEMPOTENCY_CONFLICT', 'Previous launch for this nonce is no longer usable.',
                          http_status: 409)
        end

        secret = TicketCrypto.derive_secret(
          client_id: launch.client_id,
          nonce: launch.nonce,
          launch_id: launch.id,
          key_version: launch.key_version
        )
        unless TokenDigest.secure_compare(TokenDigest.sha256_hex(secret), launch.ticket_secret_digest)
          raise Error.new('PROVIDER_UNAVAILABLE', 'Unable to rebuild launch ticket.', http_status: 503)
        end

        build_response(launch, secret)
      end

      def assert_idempotent_payload!(launch)
        assignment = AssignmentAccess.find_assignment!(@input[:assignment_id])
        same =
          launch.assignment_id.to_s == assignment.id.to_s &&
          launch.mode == @input[:mode] &&
          launch.return_origin == @input[:return_origin] &&
          (launch.subject == @input[:subject] || launch.meta.to_h['requested_subject'].to_s == @input[:subject])

        return if same

        raise Error.new('IDEMPOTENCY_CONFLICT', 'Idempotency-Key was reused with different payload.',
                        http_status: 409)
      end

      def build_response(launch, secret)
        ticket = TicketCrypto.ticket_for(launch_id: launch.id, secret: secret)
        public_origin = ENV.fetch(
          'AIENGLISH_PUBLIC_ORIGIN',
          ENV.fetch('FRONTEND_URL', ENV.fetch('AIENGLISH_WEB_ORIGIN', 'https://docai.m2mda.com'))
        ).to_s.chomp('/')

        {
          launchId: launch.id,
          enterUrl: "#{public_origin}/oauth/sso/enter?ticket=#{CGI.escape(ticket)}",
          expiresIn: [(launch.expires_at - Time.current).ceil, 1].max
        }
      end
    end
  end
end
