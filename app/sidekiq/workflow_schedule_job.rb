# frozen_string_literal: true

class workflowScheduleJob
  include Sidekiq::Worker

  queue_as :workflow_schedule_job

  sidekiq_options retry: 3, dead: true, queue: 'workflow_schedule_job', throttle: { threshold: 1, period: 10.second }

  sidekiq_retry_in { |count| 60 * 60 * 1 * count }

  sidekiq_retries_exhausted do |msg, _ex|
    _message = "error: #{msg['error_message']}"
  end

  def perform(project_workflow_id, user_id, entity_name, task_name)
    Apartment::Tenant.switch!(entity_name)
    @project_workflow = ProjectWorkflow.find(project_workflow_id)
    
    if @project_workflow.current_task
      @project_workflow.execute_next_step_execution!(@project_workflow.current_task)
    else
      @project_workflow.start_first_step_execution
    end

    if @project_workflow.status == 'finish'
      Sidekiq.remove_schedule(task_name)
    end
  rescue StandardError => e
    puts "====== error ====== error: #{e.message}"
  end
end
