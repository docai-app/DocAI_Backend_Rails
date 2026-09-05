# frozen_string_literal: true

module Oauth
  module Sso
    class AssignmentAccess
      UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

      def self.find_assignment!(assignment_id)
        candidates = lookup_candidates(assignment_id)
        assignment = nil

        candidates.each do |candidate|
          assignment = find_by_candidate(candidate)
          break if assignment
        end

        if assignment.blank?
          Rails.logger.info(
            "[Oauth::Sso::AssignmentAccess] assignment not found candidates=#{candidates.inspect}"
          )
          raise Error.new('ASSIGNMENT_NOT_FOUND', 'Assignment not found.', http_status: 404)
        end

        assignment
      end

      # Same bar as EssayAssignmentsController#aienglish_access (web code-join / upload):
      # allow when the account has this category feature (plus a few always-on categories).
      # Do not require distribution rows or existing gradings for SSO launch.
      def self.assert_can_open!(user:, assignment:)
        if user.blank?
          raise Error.new(
            'ASSIGNMENT_FORBIDDEN',
            '無法開啟作業：OAuth 綁定對應的使用者為空。',
            http_status: 403
          )
        end
        if assignment.blank?
          raise Error.new(
            'ASSIGNMENT_FORBIDDEN',
            '無法開啟作業：作業不存在。',
            http_status: 403
          )
        end

        return true if category_allowed_for_user?(user: user, assignment: assignment)

        features =
          if user.respond_to?(:aienglish_features_list)
            Array(user.aienglish_features_list).map(&:to_s)
          else
            []
          end
        detail =
          "目前帳號不能開啟這份作業：帳號未開通此 category 權限。" \
          "（user=#{user.id} category=#{assignment.category} " \
          "features=#{features.join(',').presence || '空'} " \
          "assignment=#{assignment.id} code=#{assignment.code}）"

        Rails.logger.info("[Oauth::Sso::AssignmentAccess] forbidden #{detail}")
        raise Error.new('ASSIGNMENT_FORBIDDEN', detail, http_status: 403)
      end

      # Mirrors EssayAssignmentsController#aienglish_access + EssayAssignment#category_enabled_for?
      def self.category_allowed_for_user?(user:, assignment:)
        return false if user.blank? || assignment.blank?
        return true if user.respond_to?(:aienglish_global_admin?) && user.aienglish_global_admin?

        category = assignment.category.to_s
        return true if category == 'sentence_puzzle' || category == 'talk_lab_speaking'
        return true if assignment.respond_to?(:category_enabled_for?) && assignment.category_enabled_for?(user)

        features = user.respond_to?(:aienglish_features_list) ? Array(user.aienglish_features_list).map(&:to_s) : []
        features.include?(category)
      end
      private_class_method :category_allowed_for_user?

      # Used by EssayAssignment#assigned_to_student? for web / distribution checks.
      def self.assigned_to_student?(user:, assignment:)
        return false if user.blank? || assignment.blank?

        return true if AssignmentStudentAssignment.exists?(
          essay_assignment_id: assignment.id,
          general_user_id: user.id
        )

        assigned_in_any_tenant?(assignment_id: assignment.id, user_id: user.id)
      end

      def self.assigned_in_any_tenant?(assignment_id:, user_id:)
        return false unless defined?(Apartment)

        names = apartment_tenant_names
        return false if names.blank?

        current = Apartment::Tenant.current
        names.each do |tenant|
          next if tenant.blank? || tenant.to_s == current.to_s

          found = false
          begin
            Apartment::Tenant.switch(tenant) do
              found = AssignmentStudentAssignment.exists?(
                essay_assignment_id: assignment_id,
                general_user_id: user_id
              )
            end
          rescue Apartment::TenantNotFound, StandardError => e
            Rails.logger.warn(
              "[Oauth::Sso::AssignmentAccess] tenant scan skipped tenant=#{tenant} error=#{e.class}"
            )
            next
          end
          return true if found
        end

        false
      ensure
        if defined?(Apartment) && current.present?
          begin
            Apartment::Tenant.switch!(current)
          rescue StandardError
            Apartment::Tenant.switch!('public')
          end
        end
      end

      def self.apartment_tenant_names
        raw = Apartment.tenant_names
        list = raw.respond_to?(:call) ? raw.call : raw
        Array(list).map(&:to_s)
      rescue StandardError
        []
      end
      private_class_method :apartment_tenant_names

      def self.lookup_candidates(raw)
        value = raw.to_s.strip
        return [] if value.blank?

        list = [value]

        # Content sync / composite keys: "<ownerUserId>:<assignmentUuid>"
        if value.include?(':')
          tail = value.split(':').last.to_s.strip
          list << tail if tail.present?
        end

        # Deep links accidentally passed as assignmentId.
        if value.include?('/upload/')
          code = value.split('/upload/').last.to_s.split('?').first.to_s.strip
          list << code if code.present?
        end

        list.uniq
      end
      private_class_method :lookup_candidates

      def self.find_by_candidate(candidate)
        if candidate.match?(UUID_RE)
          found = EssayAssignment.find_by(id: candidate)
          return found if found
        end

        EssayAssignment.find_by(code: candidate) ||
          EssayAssignment.find_by(code: candidate.downcase) ||
          EssayAssignment.find_by(code: candidate.upcase)
      rescue ActiveRecord::StatementInvalid, ArgumentError => e
        Rails.logger.warn("[Oauth::Sso::AssignmentAccess] lookup error=#{e.class}")
        EssayAssignment.find_by(code: candidate)
      end
      private_class_method :find_by_candidate
    end
  end
end
