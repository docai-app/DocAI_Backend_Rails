# frozen_string_literal: true

module TalkLabSpeaking
  module DifyMock
    # Global switch for Talk Lab Dify workflow mocks.
    # Set TALK_LAB_DIFY_MOCK=false (or unset) to use real Dify workflows.
    #
    # Optional future flags (not implemented in Phase 1):
    # TALK_LAB_DIFY_MOCK_PACKAGE, TALK_LAB_DIFY_MOCK_GRADING, TALK_LAB_DIFY_MOCK_GENERAL_CONTEXT
    module Policy
      module_function

      def enabled?
        return false unless mock_env_requested?

        if Rails.env.production?
          Rails.logger.error('[TalkLabDifyMock] TALK_LAB_DIFY_MOCK is set in production but will remain disabled.')
          return false
        end

        true
      end

      def mock_env_requested?
        %w[true 1].include?(ENV['TALK_LAB_DIFY_MOCK'].to_s.strip.downcase)
      end
    end
  end
end
