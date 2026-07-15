# frozen_string_literal: true

module AssignmentPackages
  class GradingLinker
    def self.call(essay_grading)
      new(essay_grading).call
    end

    def initialize(essay_grading)
      @essay_grading = essay_grading
    end

    def call
      item = @essay_grading.essay_assignment&.assignment_package_item
      return unless item
      return unless item.assignment_package.owned_by?(@essay_grading.general_user)
      return if item.essay_grading_id == @essay_grading.id

      item.update!(essay_grading: @essay_grading)
    end
  end
end
