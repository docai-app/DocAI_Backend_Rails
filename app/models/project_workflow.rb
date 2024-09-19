# frozen_string_literal: true

# == Schema Information
#
# Table name: project_workflows
#
#  id                  :uuid             not null, primary key
#  name                :string           not null
#  status              :integer          default("draft"), not null
#  description         :string
#  user_id             :uuid
#  is_process_workflow :boolean          default(FALSE)
#  deadline            :datetime
#  meta                :jsonb
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  folder_id           :uuid
#  is_template         :boolean          default(FALSE), not null
#  source_workflow_id  :uuid
#  user_type           :string           default("User"), not null
#
# Indexes
#
#  index_project_workflows_on_folder_id            (folder_id)
#  index_project_workflows_on_folder_id            (folder_id)
#  index_project_workflows_on_is_process_workflow  (is_process_workflow)
#  index_project_workflows_on_is_process_workflow  (is_process_workflow)
#  index_project_workflows_on_source_workflow_id   (source_workflow_id)
#  index_project_workflows_on_source_workflow_id   (source_workflow_id)
#  index_project_workflows_on_status               (status)
#  index_project_workflows_on_status               (status)
#
# Foreign Keys
#
#  fk_rails_...  (folder_id => folders.id)
#  fk_rails_...  (folder_id => public.folders.id)
#
class ProjectWorkflow < ApplicationRecord
  store_accessor :meta, :description, :current_task_id, :executed_times

  has_one :chatbot, dependent: :destroy, class_name: 'Chatbot', foreign_key: 'object_id'
  has_many :steps, lambda {
                     order(position: :asc)
                   }, dependent: :destroy, class_name: 'ProjectWorkflowStep', foreign_key: 'project_workflow_id'
  belongs_to :folder, optional: true, class_name: 'Folder'
  belongs_to :user, optional: true, polymorphic: true

  has_many :derives, class_name: 'ProjectWorkflow', foreign_key: 'source_workflow_id'
  belongs_to :source_workflow, class_name: 'ProjectWorkflow', optional: true

  enum status: {
    draft: 0,
    running: 1,
    finish: 2,
    paused: 3
  }

  def calc_executed_times
    # 其實即係自己有幾多個衍生物
    # 如果不是衍生物，咁就係 start! 時將 source_workflow_id 改成是自己的 id, 即自己係自己的衍生
    ProjectWorkflow.where(source_workflow_id:).count
  end

  def update_executed_times
    self['meta']['executed_times'] = calc_executed_times
    save
  end

  def duplicate!
    return nil unless is_process_workflow?

    new_workflow = dup
    new_workflow.source_workflow_id = id # 记录复制源的 ID

    transaction do
      new_workflow.save!
      steps.each do |step|
        new_step = step.dup
        new_step.project_workflow_id = new_workflow.id
        new_step.save!
      end
    end

    new_workflow
  end

  def restart!
    # 重開其實相當於複製一個新的出黎，而原本的呢個就相當於一個運行記錄了
    new_wf = duplicate!
    new_wf.steps.each do |step|
      step.update(status: 0)
    end
    new_wf.start!
  end

  def pause!
    paused!
  end

  def resume!
    running!
  end

  def start!
    update(source_workflow_id: id) if source_workflow_id.nil?

    begin
      update_executed_times
      running!
      start_first_step_execution if is_process_workflow?
    rescue StandardError => e
      puts e
      logger.error e
      false
    end
  end

  def execute_next_step_execution!(current_step_execution)
    next_step_execution = steps.find_by(position: current_step_execution.position + 1)
    if next_step_execution.present?
      next_step_execution.start!
      update_column(:meta, self['meta'].merge(current_task_id: next_step_execution.id))
    elsif steps.pluck(:status).all?('completed')
      # 如果冇下一步，即係應該做完了
      completed!
    else
      failed!
    end
  end

  def start_first_step_execution
    first_step_execution = steps.order(:position).first
    first_step_execution.start! if first_step_execution.present?
    update_column(:meta, self['meta'].merge(current_task_id: first_step_execution.id))
  end

  def current_task
    steps.find_by(id: current_task_id)
  end

  def running_task
    steps.where(status: 'running').order(:position).first
  end

  def pending_task
    steps.where(status: 'pending').order(:position).first
  end

  def starter_user
    return User.where(slack_user_id: starter_slack_user_id).first if starter_slack_user_id.present?

    nil
  end

  def show_status
    {
      "steps_status": steps.pluck(:status),
      "progress": calculate_progress(steps.pluck(:status)),
      "status": status
    }
  end

  def calculate_progress(statuses)
    total_statuses = statuses.size
    completed_count = statuses.count('completed') || 0 # 找到第一个 completed 状态的索引，如果找不到则默认为数组长度
    progress_percentage = (completed_count.to_f / total_statuses) * 100
    progress_percentage.round(2) # 四舍五入保留两位小数
  end

  ### test use functions
  def make_all_steps_complete!
    steps.each(&:complete!)
  end
end
