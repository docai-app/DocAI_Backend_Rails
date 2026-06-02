# frozen_string_literal: true

module Admin
  module EssayGradings
    # 批量修改 EssayGrading 状态（首版仅支持改为 draft）
    class BulkUpdateStatusService
      ALLOWED_TARGET_STATUSES = %w[draft].freeze
      # 允许改为 draft 的来源状态
      ALLOWED_SOURCE_STATUSES = %w[pending stopped].freeze

      def initialize(ids:, status:)
        @ids = ids
        @target_status = status.to_s
      end

      # @return [Hash] { success:, summary:, results: }
      def call
        validate_target_status!

        results = @ids.map { |id| process_one(id) }
        build_response(results)
      end

      private

      def validate_target_status!
        return if ALLOWED_TARGET_STATUSES.include?(@target_status)

        raise ArgumentError, "Unsupported target status: #{@target_status}"
      end

      def process_one(id)
        grading = EssayGrading.find_by(id: id)
        unless grading
          return failure_result(id, 'Essay grading not found', nil)
        end

        # 已是 draft 视为 noop 成功
        if grading.draft?
          return {
            id: id,
            success: true,
            message: 'Already draft',
            status: 'draft'
          }
        end

        # 仅 pending / stopped 可改为 draft；graded 等状态拒绝
        unless ALLOWED_SOURCE_STATUSES.include?(grading.status)
          return failure_result(
            id,
            'Only pending or stopped records can be changed to draft',
            grading.status
          )
        end

        # 不改 meta.grading_errors，不触发 run_workflow
        grading.admin_mark_as_draft!

        {
          id: id,
          success: true,
          message: 'Status updated to draft',
          status: 'draft'
        }
      rescue StandardError => e
        Rails.logger.error("[BulkUpdateStatus] id=#{id} status=#{@target_status} error=#{e.class}: #{e.message}")
        failure_result(id, "Failed to update status: #{e.message}", grading&.status)
      end

      def failure_result(id, message, status)
        {
          id: id,
          success: false,
          message: message,
          status: status
        }
      end

      def build_response(results)
        succeeded = results.count { |r| r[:success] }
        failed = results.size - succeeded

        Rails.logger.info(
          "[BulkUpdateStatus] target=#{@target_status} requested=#{results.size} " \
          "succeeded=#{succeeded} failed=#{failed} ids=#{@ids.join(',')}"
        )

        {
          success: true,
          summary: {
            requested: results.size,
            succeeded: succeeded,
            failed: failed
          },
          results: results
        }
      end
    end
  end
end
