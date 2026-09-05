# frozen_string_literal: true

module Oauth
  # Enqueue and prepare Partner webhook deliveries for OAuth / Assignment events.
  class WebhookDispatcher
    class << self
      def enqueue_event(application:, event_type:, data:, force: false)
        return if application.blank?

        config = application.webhook_config
        return if config.blank? || (!config.enabled && !force)
        return if config.url.blank? || config.signing_secret.blank?
        return unless force || config.subscribed_to?(event_type)

        delivery = OauthWebhookDelivery.create!(
          oauth_application: application,
          event_type: event_type.to_s,
          status: 'pending',
          payload: {}
        )

        delivery.update!(
          payload: WebhookSigner.build_envelope(
            id: delivery.id,
            type: event_type.to_s,
            client_id: application.uid,
            data: data
          )
        )

        OauthPartnerWebhookDispatchJob.perform_async(delivery.id)
        delivery
      rescue StandardError => e
        Rails.logger.warn("[Oauth::WebhookDispatcher] enqueue failed: #{e.message}")
        nil
      end

      def enqueue_assignment_distributed(distribution)
        students = distribution.assignment_student_assignments.includes(:general_user).map(&:general_user).compact
        return if students.empty?

        assignment = distribution.essay_assignment
        user_ids = students.map(&:id)
        links = OauthPartnerAccountLink.active
                                       .where(general_user_id: user_ids)
                                       .includes(:oauth_application, :general_user)

        links.find_each do |link|
          app = link.oauth_application
          next if app.blank? || !app.enabled?

          enqueue_event(
            application: app,
            event_type: 'assignment.distributed',
            data: {
              assignment: {
                id: assignment.id,
                title: assignment.title,
                topic: assignment.topic,
                code: assignment.code,
                category: assignment.category,
                deadline: distribution.deadline&.utc&.iso8601,
                url: assignment_deep_link(assignment)
              },
              distribution: {
                id: distribution.id,
                distribution_type: distribution.distribution_type,
                school_id: distribution.school_id
              },
              student: {
                general_user_id: link.general_user_id,
                email: link.general_user&.email,
                nickname: link.general_user&.nickname
              },
              partner: {
                external_user_id: link.external_user_id,
                external_site: link.external_site
              }
            }
          )
        end
      end

      def enqueue_assignment_updated(distribution)
        students = distribution.assignment_student_assignments.includes(:general_user).map(&:general_user).compact
        return if students.empty?

        assignment = distribution.essay_assignment
        user_ids = students.map(&:id)
        OauthPartnerAccountLink.active.where(general_user_id: user_ids).includes(:oauth_application, :general_user).find_each do |link|
          app = link.oauth_application
          next if app.blank? || !app.enabled?

          enqueue_event(
            application: app,
            event_type: 'assignment.updated',
            data: {
              assignment: {
                id: assignment.id,
                title: assignment.title,
                deadline: distribution.deadline&.utc&.iso8601,
                url: assignment_deep_link(assignment)
              },
              distribution: { id: distribution.id },
              student: {
                general_user_id: link.general_user_id,
                email: link.general_user&.email,
                nickname: link.general_user&.nickname
              },
              partner: {
                external_user_id: link.external_user_id,
                external_site: link.external_site
              }
            }
          )
        end
      end

      def enqueue_binding_revoked(link, reason: 'user_revoke_binding')
        return if link.blank?

        enqueue_event(
          application: link.oauth_application,
          event_type: 'oauth.binding.revoked',
          data: {
            general_user_id: link.general_user_id,
            external_user_id: link.external_user_id,
            external_site: link.external_site,
            revoked_at: (link.revoked_at || Time.current).utc.iso8601,
            reason: reason
          }
        )
      end

      def enqueue_assignment_lifecycle(user:, assignment:, grading:, event_type:)
        return if user.blank? || assignment.blank?

        OauthPartnerAccountLink.active.where(general_user_id: user.id).includes(:oauth_application).find_each do |link|
          app = link.oauth_application
          next if app.blank? || !app.enabled?

          enqueue_event(
            application: app,
            event_type: event_type,
            data: {
              subject: user.id.to_s,
              assignmentId: assignment.id.to_s,
              completedAt: (grading&.updated_at || Time.current).utc.iso8601(3),
              reportUrl: grading.present? ? "#{frontend_base}/essay/grading/#{grading.id}" : nil,
              partner: {
                external_user_id: link.external_user_id,
                external_site: link.external_site
              }
            }.compact
          )
        end
      end

      private

      def frontend_base
        ENV.fetch('AIENGLISH_PUBLIC_ORIGIN',
                  ENV.fetch('FRONTEND_URL', ENV.fetch('AIENGLISH_WEB_ORIGIN', 'https://docai.m2mda.com'))).to_s.chomp('/')
      end

      def assignment_deep_link(assignment)
        path = ::Oauth::Sso::AssignmentPathBuilder.path_for(assignment).sub(/\?embed=1\z/, '')
        "#{frontend_base}#{path}"
      rescue StandardError
        "#{frontend_base}/assignments/#{assignment.id}"
      end
    end
  end
end
