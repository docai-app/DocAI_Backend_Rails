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

      def self.assert_can_open!(user:, assignment:)
        unless assignment.assigned_to_student?(user)
          raise Error.new('ASSIGNMENT_FORBIDDEN', 'The assignment is not available to this subject.', http_status: 403)
        end

        true
      end

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
