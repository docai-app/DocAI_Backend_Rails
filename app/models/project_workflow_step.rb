# frozen_string_literal: true

# == Schema Information
#
# Table name: project_workflow_steps
#
#  id                  :uuid             not null, primary key
#  position            :integer
#  name                :string           not null
#  description         :string
#  user_id             :uuid
#  project_workflow_id :uuid
#  status              :integer          default("pending")
#  is_human            :boolean          default(TRUE)
#  meta                :jsonb
#  dag_meta            :jsonb
#  deadline            :datetime
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  assignee_id         :uuid
#  user_type           :string           default("User"), not null
#
# Indexes
#
#  index_project_workflow_steps_on_project_workflow_id  (project_workflow_id)
#  index_project_workflow_steps_on_project_workflow_id  (project_workflow_id)
#  index_project_workflow_steps_on_status               (status)
#  index_project_workflow_steps_on_status               (status)
#  index_project_workflow_steps_on_user_id              (user_id)
#  index_project_workflow_steps_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (project_workflow_id => public.project_workflows.id)
#  fk_rails_...  (project_workflow_id => project_workflows.id)
#  fk_rails_...  (user_id => public.users.id)
#  fk_rails_...  (user_id => users.id)
#
class ProjectWorkflowStep < ApplicationRecord
  include AASM
  acts_as_list scope: :project_workflow

  store_accessor :meta, :started_at, :criteria, :custom_conditions, :description, :notification_interval,
                 :notification_last_sent_at, :log_data, :notification_method
  store_accessor :dag_meta, :dag_id, :dag_run_id, :dag_name

  belongs_to :user, class_name: 'User', polymorphic: true, optional: true
  belongs_to :assignee, class_name: 'User', foreign_key: 'assignee_id', optional: true
  belongs_to :project_workflow, optional: true, class_name: 'ProjectWorkflow', foreign_key: 'project_workflow_id'

  before_save :store_assignee_id
  before_save :set_custom_conditions_from_dag

  after_save :handle_assignee_change

  scope :has_dag, -> { where("dag_meta->>'dag_id' IS NOT NULL") }

  enum status: {
    pending: 0,
    running: 1,
    completed: 2,
    failed: 3
  }

  def store_assignee_id
    @old_assignee_id = assignee_id_was if assignee_id_changed?
  end

  # Attributes related macros
  def handle_assignee_change
    return unless saved_change_to_assignee_id?

    if !project_workflow_id.nil?
      chatbot = Chatbot.find_by(object_id: project_workflow_id, object_type: 'ProjectWorkflow')
      puts chatbot.inspect
      if chatbot.add_message('system', 'talk', "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}",
                             { belongs_user_id: assignee_id })
        puts "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}"
        ActionCable.server.broadcast(
          "chat_ProjectWorkflow_#{chatbot.id}_#{assignee_id}", {
            message: "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}",
            chatbot_id: chatbot.id,
            assignee_id:
          }
        )
      end
    else
      puts 'No project workflow id!'
      chatbot = Chatbot.find_by(object_id: assignee_id, object_type: 'UserSystemAssistant')
      puts 'Chatbot: ', chatbot.inspect
      if chatbot.add_message('system', 'talk', "#{name} has assigned to #{assignee.email}",
                             { belongs_user_id: assignee_id })
        puts "#{name} has assigned to #{assignee.email}"
        ActionCable.server.broadcast(
          "chat_SystemAssistant_#{chatbot.id}_#{assignee_id}", {
            message: "#{name} has assigned to #{assignee.email}",
            chatbot_id: chatbot.id,
            assignee_id:
          }
        )
      end
    end
  end

  aasm column: 'status', enum: true do
    state :pending, initial: true
    state :running
    state :completed
    state :failed

    event :start do
      transitions from: :pending, to: :running, after: proc { execute! }
    end

    event :finish do
      transitions from: :running, to: :completed, after: proc { set_log_data('finish') }
    end

    event :cancel do
      transitions from: :completed, to: :running, after: proc { set_log_data('cancel') }
    end

    # after_transition on: :start, do: :send_notification_if_status_changed
  end

  def set_log_data(action)
    self['meta']['log_data'] ||= []

    case action
    when 'start'
      self['meta']['log_data'].append({ time: DateTime.current, msg: "#{project_workflow.name} 開始" })
    when 'finish'
      self['meta']['log_data'].append({ time: DateTime.current, msg: "#{project_workflow.name} 完成" })
    when 'cancel'
      self['meta']['log_data'].append({ time: DateTime.current, msg: "#{project_workflow.name} 重做" })
    end
    save

    # 呢道睇要求了，邊D事件要觸發咩通知，就將D通知寫呢道
    # send_notification_by_type
  end

  enum notification_type: { one_time: 0, interval: 1 }

  def send_notification
    if one_time?
      send_one_time_notification
    elsif interval?
      send_interval_notification
    end
  end

  def send_one_time_notification
    return if notification_last_sent_at.present?

    # 调用相应的通知方法
    send_notification_by_type

    update(notification_last_sent_at: Time.now)
  end

  def send_interval_notification
    return if notification_last_sent_at.nil?

    # 检查是否满足发送通知的时间间隔
    return unless enough_time_passed?

    # 调用相应的通知方法
    send_notification_by_type

    update(notification_last_sent_at: Time.now)
  end

  def send_notification_by_type
    case notification_method
    when 'slack'
      send_slack_notification
    when 'in_app'
      send_in_app_notification
    when 'email'
      send_email_notification
    else
      send_in_app_notification # default
    end
  end

  def get_assigness
    # (User.where(id: assignees) + [workflow_execution.starter_user]).compact.uniq
  end

  def send_in_app_notification
    # 发送应用内通知给 assignee
    # 这里是示例代码，你需要根据实际情况进行实现
    # InAppNotificationService.send_set_log_data(assignee, log_data[:message])
    if chatbot.add_message('system', 'talk', "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}",
                           { belongs_user_id: assignee_id })
      puts "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}"
      ActionCable.server.broadcast(
        "chat_ProjectWorkflow_#{chatbot.id}_#{assignee_id}", {
          message: "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}",
          chatbot_id: chatbot.id,
          assignee_id:
        }
      )
    end
  end

  def send_email_notification
    # 发送邮件通知给 assignee
    # 这里是示例代码，你需要根据实际情况进行实现
    # EmailNotificationService.send_set_log_data(assignee, log_data[:message])
  end

  def enough_time_passed?
    minutes_passed = (Time.now - notification_last_sent_at) / 60
    minutes_passed >= notification_interval
  end

  def execute!
    self['meta']['started_at'] = DateTime.current
    save

    set_log_data('start')

    return if is_human? # 人類工作就咁了
    return if dag_id.nil? # 未設定好 dag_id

    # 檢查這個 dag 需要的 input 是否已經填好
    return false unless fulfill_criteria?

    # 執行一次這個 dag
    dr = DagRun.new(user_id:, dag_name: dag.name)
    dr.project_workflow_step_id = id
    dr.save
    dr.reset_workflow!

    self['dag_meta']['dag_run_id'] = dr.id
    save

    # 開始這個 dag run
    dr.start
  end

  def complete!
    return unless fulfill_criteria?

    complete
  end

  def complete
    # update(status: "completed", completed_at: DateTime.current)
    finish!
    project_workflow.execute_next_step_execution!(self)
  end

  def fulfill_criteria?
    return true if custom_conditions.blank?

    conditions = custom_conditions
    unless evaluate_conditions(conditions, criteria)
      errors.add(:base, '必要條件未滿足')
      return false
    end

    true
  end

  def dag
    Dag.where(id: dag_id).first
  end

  def set_custom_conditions_from_dag
    # 根據 dag 中的 meta['workflow'] 入邊的 inputs 去生成 custom_conditions
    return unless dag_id_changed?

    return if dag_id.nil?

    self['meta']['custom_conditions'] = {
      "condition_type": 'and',
      "conditions": dag['meta']['inputs'].map do |key, _value|
        {
          "condition_type": 'field_presence',
          "field_name": key.downcase
        }
      end
    }
    self['dag_meta']['dag_name'] = dag.name
  end

  protected

  def evaluate_condition(condition, json_data)
    condition_type = condition['condition_type']
    case condition_type
    when 'and'
      return false unless evaluate_and_conditions(condition['conditions'], json_data)
    when 'or'
      return false unless evaluate_or_conditions(condition['conditions'], json_data)
    when 'field_presence'
      return false unless evaluate_field_presence_condition(condition['field_name'], json_data)
    when 'field_inclusion'
      return false unless evaluate_field_inclusion_condition(condition['field_name'], condition['values'], json_data)
    else
      return false
    end
    true
  end

  def evaluate_conditions(conditions, json_data)
    return true if conditions.blank?

    # 如果 conditions 係個 array, 咁佢要 each, 如果唔係 array, 就唔洗 each
    if conditions.is_a?(Array)
      conditions.each do |condition|
        return false unless evaluate_condition(condition, json_data)
      end
    else
      return false unless evaluate_condition(conditions, json_data) # 佢唔係 array, 直接傳入去
    end

    true
  end

  def evaluate_and_conditions(conditions, json_data)
    conditions.all? { |condition| evaluate_conditions(condition, json_data) }
  end

  def evaluate_or_conditions(conditions, json_data)
    conditions.any? { |condition| evaluate_conditions(condition, json_data) }
  end

  def evaluate_field_presence_condition(field_name, json_data)
    return false if json_data.blank?

    json_data.key?(field_name)
  end

  def evaluate_field_inclusion_condition(field_name, values, json_data)
    return false if json_data.blank?

    json_hash = JSON.parse(json_data)
    field_value = json_hash[field_name]
    values.include?(field_value)
  end
end
