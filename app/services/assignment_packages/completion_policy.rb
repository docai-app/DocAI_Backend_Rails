# frozen_string_literal: true

module AssignmentPackages
  class CompletionPolicy
    def self.completed?(essay_grading)
      essay_grading.present? && !essay_grading.draft?
    end
  end
end
