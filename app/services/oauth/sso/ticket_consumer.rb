# frozen_string_literal: true

module Oauth
  module Sso
    class TicketConsumer
      SESSION_TTL_SECONDS = Integer(ENV.fetch('OAUTH_SSO_EMBED_SESSION_TTL_SECONDS', '7200'))

      def initialize(ticket:)
        @ticket = ticket
      end

      def call
        parsed = TicketCrypto.parse_ticket(@ticket)

        OauthEmbedLaunch.transaction do
          launch = OauthEmbedLaunch.lock.find_by(id: parsed[:launch_id])
          raise enter_error(400, '启动链接无效，请返回 KonnecAI 再试一次。') if launch.blank?

          digest = TokenDigest.sha256_hex(parsed[:secret])
          unless TokenDigest.secure_compare(digest, launch.ticket_secret_digest)
            raise enter_error(400, '启动链接无效，请返回 KonnecAI 再试一次。')
          end
          raise enter_error(410, '启动链接已过期，请返回 KonnecAI 重新开启。') if launch.expires_at <= Time.current
          raise enter_error(410, '启动链接已使用，请返回 KonnecAI 重新开启。') if launch.consumed?
          raise enter_error(410, '启动链接已失效，请返回 KonnecAI 重新开启。') if launch.revoked?

          application = OauthApplication.find_by(uid: launch.client_id)
          raise enter_error(403, 'AIEnglish 链接已失效，请返回 KonnecAI 重新链接。') if application.blank? || !application.enabled?

          binding = begin
            BindingResolver.require_active!(application: application, subject: launch.subject)
          rescue Error
            raise enter_error(403, 'AIEnglish 链接已失效，请返回 KonnecAI 重新链接。')
          end

          assignment = EssayAssignment.find_by(id: launch.assignment_id)
          raise enter_error(404, '找不到这份作业。') if assignment.blank?

          begin
            AssignmentAccess.assert_can_open!(user: binding.general_user, assignment: assignment)
          rescue Error
            raise enter_error(403, '目前账号不能开启这份作业。')
          end

          session_id = SecureRandom.uuid
          session_secret = SecureRandom.random_bytes(32)
          session = OauthEmbedSession.create!(
            id: session_id,
            session_secret_digest: TokenDigest.sha256_hex(session_secret),
            client_id: launch.client_id,
            subject: launch.subject,
            user_id: binding.general_user_id,
            assignment_id: assignment.id,
            launch_id: launch.id,
            parent_origin: launch.return_origin,
            mode: launch.mode,
            expires_at: SESSION_TTL_SECONDS.seconds.from_now,
            last_seen_at: Time.current,
            meta: { request_id: launch.request_id }
          )

          updated = OauthEmbedLaunch.where(
            id: launch.id,
            ticket_secret_digest: digest,
            consumed_at: nil,
            revoked_at: nil
          ).where('expires_at > ?', Time.current)
                                    .update_all(consumed_at: Time.current, embed_session_id: session.id)

          raise enter_error(410, '启动链接已使用，请返回 KonnecAI 重新开启。') if updated != 1

          {
            session: session,
            session_token: "#{session.id}.#{Base64.urlsafe_encode64(session_secret, padding: false)}",
            assignment: assignment,
            redirect_path: AssignmentPathBuilder.path_for(assignment)
          }
        end
      end

      private

      def enter_error(status, message)
        Error.new('ENTER_FAILED', message, http_status: status)
      end
    end
  end
end
