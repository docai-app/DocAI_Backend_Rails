# frozen_string_literal: true

module WebSso
  class ResultDestination
    ALLOWED_STATUSES = %w[pending graded stopped].freeze
    STANDARD_RESULT_CATEGORIES = %w[
      essay
      sentence_builder
      sentence_puzzle
      speaking_conversation
      speaking_essay
      speaking_pronunciation
    ].freeze

    class ResultNotAvailableError < StandardError; end

    def self.path_for(grading)
      new(grading).path
    end

    def initialize(grading)
      @grading = grading
    end

    def path
      unless ALLOWED_STATUSES.include?(@grading.status.to_s)
        raise ResultNotAvailableError, 'This submission does not have a web result yet.'
      end

      category = @grading.essay_assignment&.category.to_s
      return comprehension_path if category == 'comprehension'
      return "/essay/grading/#{@grading.id}" if STANDARD_RESULT_CATEGORIES.include?(category)

      raise ResultNotAvailableError, 'This assignment type does not have a supported student result page.'
    end

    private

    def comprehension_path
      path = "/comprehension/show/#{@grading.id}"
      return path if @grading.newsfeed_id.blank?

      "#{path}?#{Rack::Utils.build_query(newsfeed_id: @grading.newsfeed_id)}"
    end
  end
end
