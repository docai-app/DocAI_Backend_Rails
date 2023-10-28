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
#
class ProjectWorkflowStep < ApplicationRecord

  acts_as_list scope: :project_workflow

  store_accessor :meta, :started_at, :criteria, :custom_conditions, :description
  store_accessor :dag_meta, :dag_id, :dag_run_id

  belongs_to :user, class_name: 'User', foreign_key: 'user_id', optional: true
  belongs_to :assignee, class_name: 'User', foreign_key: 'assignee_id', optional: true
  belongs_to :project_workflow, optional: true, class_name: 'ProjectWorkflow', foreign_key: 'project_workflow_id'

  before_save :store_assignee_id
  before_save :set_custom_conditions_from_dag

  after_save :handle_assignee_change

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
          "chat_ProjectWorkflow_#{chatbot.id}_#{assignee_id}", { message: "#{project_workflow.name}'s #{name} has assigned to #{assignee.email}" }
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
          "chat_SystemAssistant_#{chatbot.id}_#{assignee_id}", { message: "#{name} has assigned to #{assignee.email}" }
        )
      end
    end
  end

  def start
    started_at = DateTime.current
    save

    return if human? # 人類工作就咁了
    return if dag_id.nil? # 未設定好 dag_id

    # 檢查這個 dag 需要的 input 是否已經填好
    if fulfill_criteria?
      # 執行一次這個 dag
      dr = DagRun.new(user_id: user_id, dag_name: dag.name)
      dr.save
      dr.reset_workflow!

      self['dag_meta']['dag_run_id'] = dr.id
      save

      # 開始這個 dag run
      dr.start
    else
      return false
    end
  end
  
  def fulfill_criteria?
    return true if custom_conditions.blank?

    conditions = custom_conditions
    unless evaluate_conditions(conditions, criteria)
      errors.add(:base, "必要條件未滿足")
      return false
    end

    return true
  end

  def dag
    Dag.where(id: dag_id).first
  end

  def set_custom_conditions_from_dag
    # 根據 dag 中的 meta['workflow'] 入邊的 inputs 去生成 custom_conditions
    return unless dag_id_changed?
    
    if dag_id.nil?
      custom_conditions = nil
      return 
    end

    self['meta']['custom_conditions'] = {
      "condition_type": "and",
      "conditions": dag['meta']['inputs'].map do |key, value|
        {
          "condition_type": "field_presence",
          "field_name": key.downcase
        }
      end
    }
  end

  protected
  
  def evaluate_condition(condition, json_data)
    condition_type = condition["condition_type"]
    case condition_type
    when "and"
      return false unless evaluate_and_conditions(condition["conditions"], json_data)
    when "or"
      return false unless evaluate_or_conditions(condition["conditions"], json_data)
    when "field_presence"
      return false unless evaluate_field_presence_condition(condition["field_name"], json_data)
    when "field_inclusion"
      return false unless evaluate_field_inclusion_condition(condition["field_name"], condition["values"], json_data)
    else
      return false
    end
    return true
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
