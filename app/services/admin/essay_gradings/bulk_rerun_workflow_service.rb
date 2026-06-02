# frozen_string_literal: true

module Admin
  module EssayGradings
    # 批量重新运行批改工作流：每条独立处理，单条失败不影响其余记录
    class BulkRerunWorkflowService
      RERUNABLE_STATUSES = %w[pending stopped].freeze

      def initialize(ids:)
        @ids = ids
      end

      # @return [Hash] { success:, summary:, results: }
      def call
        results = @ids.map { |id| process_one(id) }
        build_response(results)
      end

      private

      def process_one(id)
        grading = EssayGrading.find_by(id: id)
        unless grading
          return failure_result(id, 'Essay grading not found', nil)
        end

        # 仅 pending / stopped 允许重跑
        unless RERUNABLE_STATUSES.include?(grading.status)
          return failure_result(
            id,
            'Essay grading is not in pending or stopped status',
            grading.status
          )
        end

        # rerun_workflow：清错误 meta → pending → Sidekiq 入队
        grading.rerun_workflow

        {
          id: id,
          success: true,
          message: 'Workflow rerun queued',
          status: 'pending'
        }
      rescue StandardError => e
        Rails.logger.error("[BulkRerunWorkflow] id=#{id} error=#{e.class}: #{e.message}")
        failure_result(id, "Failed to rerun workflow: #{e.message}", grading&.status)
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
          "[BulkRerunWorkflow] requested=#{results.size} succeeded=#{succeeded} failed=#{failed} " \
          "ids=#{@ids.join(',')}"
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
