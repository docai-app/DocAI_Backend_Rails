# frozen_string_literal: true

class AssignmentDistribution < ApplicationRecord
  belongs_to :essay_assignment
  belongs_to :school_academic_year
  belongs_to :school
  belongs_to :target_student, class_name: 'GeneralUser', optional: true

  has_many :assignment_student_assignments, dependent: :destroy

  enum status: {
    active: 0,
    cancelled: 1
  }

  enum distribution_type: {
    class_name: 'class_name',    # 按班級分配
    individual: 'individual'      # 按個別學生分配
  }

  validates :distribution_type, presence: true
  validates :deadline, presence: true
  validate :target_must_be_present
  validate :target_must_be_in_current_school_and_year
  validate :deadline_after_creation

  after_create :create_student_assignments
  after_update :update_student_assignments, if: :saved_change_to_deadline?
  # OAuth Partner 出站 Webhook：见下方 enqueue_partner_webhook_* 注释
  after_create :enqueue_partner_webhook_distributed
  after_update :enqueue_partner_webhook_updated, if: :saved_change_to_deadline?

  # 獲取分配目標的所有學生
  def target_students
    case distribution_type
    when 'class_name'
      StudentEnrollment
        .joins(:school_academic_year)
        .where(school_academic_years: { id: school_academic_year_id })
        .where(class_name: target_class_name, status: :active)
        .includes(:general_user)
        .map(&:general_user)
        .compact
    when 'individual'
      target_student ? [target_student] : []
    else
      []
    end
  end

  private

  def target_must_be_present
    case distribution_type
    when 'class_name'
      errors.add(:target_class_name, '班級名稱不能為空') if target_class_name.blank?
    when 'individual'
      errors.add(:target_student_id, '學生不能為空') if target_student_id.blank?
    end
  end

  def target_must_be_in_current_school_and_year
    return unless school_academic_year

    case distribution_type
    when 'class_name'
      enrollment_count = StudentEnrollment
        .joins(:school_academic_year)
        .where(school_academic_years: { id: school_academic_year_id })
        .where(class_name: target_class_name, status: :active)
        .count

      if enrollment_count.zero?
        errors.add(:base, '指定的班級在當前學年中沒有學生')
      end
    when 'individual'
      return unless target_student

      enrollment = target_student.student_enrollments
                                  .joins(:school_academic_year)
                                  .where(school_academic_years: { 
                                    id: school_academic_year_id,
                                    school_id: school_id 
                                  })
                                  .where(status: :active)
                                  .first

      unless enrollment
        errors.add(:target_student_id, '該學生不在當前學校的當前學年中')
      end
    end
  end

  def deadline_after_creation
    return unless deadline.present?

    # 使用 Time.current 而不是 created_at，因为创建时 created_at 可能还未设置
    if deadline <= Time.current
      errors.add(:deadline, '截止日期必須在當前時間之後')
    end
  end

  def create_student_assignments
    students = target_students
    return if students.empty?

    assignments = students.map do |student|
      AssignmentStudentAssignment.new(
        essay_assignment: essay_assignment,
        general_user: student,
        assignment_distribution: self,
        deadline: deadline,
        status: :assigned
      )
    end

    # 使用 bulk insert 提高性能
    # 如果使用 activerecord-import gem
    if defined?(ActiveRecord::Import)
      AssignmentStudentAssignment.import(assignments, validate: true, on_duplicate_key_ignore: true)
    else
      # 批量插入的替代方案
      assignments.each do |assignment|
        assignment.save unless AssignmentStudentAssignment.exists?(
          essay_assignment_id: assignment.essay_assignment_id,
          general_user_id: assignment.general_user_id
        )
      end
    end
  end

  def update_student_assignments
    assignment_student_assignments
      .where(status: [:assigned, :overdue])
      .update_all(deadline: deadline, updated_at: Time.current)
  end

  # ---------------------------------------------------------------------------
  # OAuth Partner Webhook（第三方站点作业推送）
  #
  # 背景：
  #   老师在 AIEnglish 向学生分配作业后，若该学生已绑定某个 OAuth Client
  #   （oauth_partner_account_links.status = active），且该 Client 在管理后台
  #   启用了 Webhook（oauth_application_webhooks.enabled = true），则向 Partner
  #   配置的 HTTPS URL 推送 signed JSON 事件。
  #
  # 触发时机（本模型回调）：
  #   - after_create  → enqueue_partner_webhook_distributed
  #       事件类型：assignment.distributed
  #       须在 create_student_assignments 之后执行（同为 after_create，
  #       按定义顺序保证学生作业行已写入，Dispatcher 才能按学生查绑定）。
  #   - after_update（仅 deadline 变更）→ enqueue_partner_webhook_updated
  #       事件类型：assignment.updated
  #
  # 实际投递：
  #   Oauth::WebhookDispatcher 创建 oauth_webhook_deliveries 记录后，
  #   由 Sidekiq Job OauthPartnerWebhookDispatchJob 异步 POST（HMAC-SHA256 签名）。
  #
  # 失败策略：
  #   此处 rescue 仅吞掉「入队/组装」异常，避免 Webhook 故障回滚作业分发事务。
  #   HTTP 投递失败由 Job 侧重试 / dead_letter，见投递日志 Admin UI。
  #
  # 文档：
  #   docs/AIEnglish_第三方绑定与作业推送对接文档_KonnecAI_2026_08_27_zh.md
  #   docs/oauth_partner_账号绑定统计与作业推送实施方案_2026_08_27_zh.md
  # ---------------------------------------------------------------------------

  # 新建分发成功后：向已绑定且启用推送的 Partner 发送 assignment.distributed
  def enqueue_partner_webhook_distributed
    Oauth::WebhookDispatcher.enqueue_assignment_distributed(self)
  rescue StandardError => e
    Rails.logger.warn("[AssignmentDistribution] partner webhook enqueue failed: #{e.message}")
  end

  # 分发 deadline 变更后：向相关 Partner 发送 assignment.updated
  def enqueue_partner_webhook_updated
    Oauth::WebhookDispatcher.enqueue_assignment_updated(self)
  rescue StandardError => e
    Rails.logger.warn("[AssignmentDistribution] partner webhook update enqueue failed: #{e.message}")
  end

  # 後台任務將在任務6中實現
  # def enqueue_distribution_notification
  #   AssignmentDistributionNotificationJob.perform_async(id)
  # end
end
