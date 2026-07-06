# frozen_string_literal: true

module AssignmentPackages
  class ProgressUpdater
    def self.call(essay_grading)
      new(essay_grading).call
    end

    def initialize(essay_grading)
      @essay_grading = essay_grading
    end

    def call
      return unless CompletionPolicy.completed?(@essay_grading)

      item = AssignmentPackageItem
             .joins(:assignment_package)
             .includes(:assignment_package)
             .find_by(
               essay_assignment_id: @essay_grading.essay_assignment_id,
               assignment_packages: { general_user_id: @essay_grading.general_user_id }
             )
      return unless item

      AssignmentPackage.transaction do
        complete_item!(item)
        unlock_next_item!(item)
        item.assignment_package.refresh_progress!
      end

      item.assignment_package
    end

    private

    def complete_item!(item)
      return if item.completed?

      item.update!(
        status: :completed,
        essay_grading: @essay_grading,
        completed_at: Time.current
      )
    end

    def unlock_next_item!(item)
      return unless item.assignment_package.active? || item.assignment_package.completed?

      next_item = item.assignment_package.assignment_package_items
                      .where('position > ?', item.position)
                      .locked
                      .order(:position)
                      .first
      return unless next_item

      next_item.update!(status: :available, unlocked_at: Time.current)
    end
  end
end
