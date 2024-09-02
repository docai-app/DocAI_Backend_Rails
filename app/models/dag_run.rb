# frozen_string_literal: true

# == Schema Information
#
# Table name: dag_runs
#
#  id               :uuid             not null, primary key
#  user_id          :uuid
#  dag_name         :string
#  dag_status       :integer          default("pending"), not null
#  meta             :jsonb
#  statistic        :jsonb
#  dag_meta         :jsonb
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  airflow_accepted :boolean          default(FALSE), not null
#  tanent           :string
#  user_type        :string           default("User"), not null
#
# Indexes
#
#  index_dag_runs_on_airflow_accepted  (airflow_accepted)
#  index_dag_runs_on_airflow_accepted  (airflow_accepted)
#  index_dag_runs_on_dag_status        (dag_status)
#  index_dag_runs_on_dag_status        (dag_status)
#  index_dag_runs_on_tanent            (tanent)
#  index_dag_runs_on_tanent            (tanent)
#  index_dag_runs_on_user_id           (user_id)
#  index_dag_runs_on_user_id           (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#  fk_rails_...  (user_id => public.users.id)
#
class DagRun < ApplicationRecord
  store_accessor :meta, :status_stack, :params, :project_workflow_step_id, :chatbot_id
  store_accessor :statistic, :current_progress, :blocking_by_user, :notification_sent
  store_accessor :dag_meta, :workflow, :input_params

  # status_stack 的格式
  # [
  #   {"name"=>"task1", "content"=>"xxxx"},
  #   {"name"=>"task2", "content"=>"xxx"},
  #   {"name"=>"task3", "content"=>"xxxxxx"}
  # ]

  belongs_to :user, optional: true, polymorphic: true

  after_update :handle_finish_status, if: :status_changed_to_finish?

  enum dag_status: { pending: 0, in_progress: 1, finish: 2 }
  # TODO: 整個 dag 的 status 都記得要更新, 多數時間係 in_progress

  def initialize(*args)
    super(*args)
    self['meta']['status_stack'] ||= []
    self['statistic']['notification_sent'] ||= false
    self['statistic']['current_progress'] ||= 0
  end

  def status_changed_to_finish?
    previous_changes['dag_status'].present? && dag_status == 'finish'
  end

  def chatbot
    return if chatbot_id.nil?

    Chatbot.find(chatbot_id)
  end

  def handle_finish_status
    # 在状态更新为 'finish' 后执行的逻辑
    # 执行您需要的动作
    puts '更新返去對應的 project workflow step 狀態'
    pws = ProjectWorkflowStep.where("dag_meta->>'dag_run_id' = ?", id.to_s).first
    pws.completed! if pws.present?

    # 例如：
    # 发送通知邮件
    # 更新相关记录
    # 触发其他业务逻辑
    return unless finish? && chatbot_id.present?

    chatbot = Chatbot.find(self['meta']['chatbot_id'])
    msg = {
      input_params:,
      output: status_stack
    }
    message_come_from = pws.present? ? 'project_workflow_step' : 'chain_feature'
    chatbot.add_message('system', 'talk', msg.to_json, { message_come_from: })
    ActionCable.server.broadcast(
      "chat_#{chatbot.id}", {
        message: msg.to_json,
        chatbot_id: chatbot.id
      }
    )

    # if self['meta']['user_type'] == 'GeneralUser'
    #   GeneralUserFeed.create('file_type' => Utils.determine_file_type(self.meta['status_stack'].last['content']), 'file_content' => self.meta['status_stack'].last['content'], 'user_id' => self['meta']['user_id'], 'user_marketplace_item_id' => self['meta']['user_marketplace_item_id'])
    # end
  end

  def reset_init!
    self['meta']['status_stack'] ||= []
    self['statistic']['notification_sent'] ||= false
    self['statistic']['current_progress'] ||= 0
    save
  end

  def as_json(options = {})
    super(options.merge(methods: [:show_status])).merge(show_status).except('show_status')
  end

  def reset_workflow!
    self['dag_meta']['workflow'] = dag.try(:[], 'meta').try(:[], 'workflow').try(:keys) || []
    self['dag_meta']['input_params'] = dag.input_params if dag.present?
    save
  end

  def progress
    completed_tasks_count = status_stack.try(:count) || 0

    total_tasks_count = workflow.size
    (completed_tasks_count.to_f / total_tasks_count * 100).round(2)
  end

  def current_task
    status_task_names = status_stack.map { |task| task['task_name'] }

    workflow.each do |task|
      return task unless status_task_names.include?(task)
    end

    nil # 如果没有找到当前进行中的任务，则返回 nil
  end

  def show_status
    {
      progress:,
      current_task:
    }
  end

  # 開始執行呢個 dag
  def start
    AirflowService.run_dag(self)
  end

  def dag
    Dag.where(name: dag_name).first
  end

  def find_status_stack_by_key(key)
    status_stack.find { |obj| obj.key?('name') && obj['name'] == key }
  end

  def add_or_replace_status_stack(obj)
    existing_index = status_stack.index { |item| item.key?('name') && item['name'] == obj['name'] }
    if existing_index
      status_stack[existing_index] = obj
    else
      status_stack << obj
    end
  end

  def add_to_status_stack(item)
    status_stack << item
  end

  def remove_from_status_stack(item)
    status_stack.delete(item)
  end

  def clear_status_stack
    status_stack.clear
  end

  def status_stack_length
    status_stack.length
  end

  def check_status_finish(name = nil)
    if name.present?
      status_object = status_stack.find { |item| item.key?('name') && item['name'] == name }
      return false unless status_object

      status_object['status'] == 'finish'
    else
      status_stack
    end
  end

  def response_url
    # 根據 user id 讀返個 domain 出黎
    subdomain = user.email.split('@')[1].split('.')[0]
    # "https://#{subdomain}.m2mda.com/api/v1/dag_runs/#{id}"

    "https://docai-dev.m2mda.com/api/v1/dag_runs/#{id}?subdomain=#{subdomain}"
  end

  def dag_status_check!
    p = progress
    if p.to_i >= 100
      self['dag_status'] = 2
      self['statistic']['current_progress'] = 100
    else
      self['dag_status'] = 1
      self['statistic']['current_progress'] = p
    end
    save
  end

  # callback methods
end
