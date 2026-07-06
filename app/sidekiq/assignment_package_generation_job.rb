# frozen_string_literal: true

class AssignmentPackageGenerationJob
  include Sidekiq::Worker

  sidekiq_retries_exhausted do |msg, ex|
    assignment_package = AssignmentPackage.find_by(id: msg['args']&.first)
    next unless assignment_package

    assignment_package.update(
      status: :failed,
      error: {
        'message' => ex.message,
        'error_class' => ex.class.name,
        'stage' => 'job_retries_exhausted',
        'occurred_at' => Time.current.iso8601
      }
    )
  end

  def perform(assignment_package_id)
    assignment_package = AssignmentPackage.find(assignment_package_id)
    AssignmentPackages::GenerationService.new(assignment_package).call
  end
end
