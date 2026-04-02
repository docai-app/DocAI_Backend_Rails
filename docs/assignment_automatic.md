# AI ENGLISH - 作業自動分派系統實現文檔

## 1. 概述

### 1.1 背景與問題

目前系統中，老師創建作業後，學生需要手動輸入作業代碼（code）才能加入。這種方式存在以下問題：

- **操作繁瑣**：學生需要記住或複製作業代碼，容易出錯
- **缺乏自動化**：無法批量分派作業給特定年級、班級或學生
- **無截止日期管理**：無法設定作業截止時間，缺乏時間管理
- **無統計功能**：老師無法快速查看作業完成情況
- **無提醒機制**：無法主動提醒未完成作業的學生

### 1.2 目標與需求

本系統旨在實現以下功能：

1. **自動分派作業**
   - 老師創建作業後，可在新頁面勾選年級、班別或個別學生進行分派
   - 老師只能選擇本學校內當前學年的學生
   - 無需再使用作業代碼

2. **學生自動接收**
   - 學生登入後，系統自動顯示待完成的作業清單
   - 顯示作業狀態：待完成、進行中、已完成、已逾期

3. **截止日期管理**
   - 老師可設定作業截止日期（deadline）
   - 系統自動判斷作業是否逾期

4. **統計與追蹤**
   - 老師可查看各學生的「已交／未交／逾期」狀態
   - 提供班級級別的統計數據

5. **提醒通知機制**
   - 老師可一鍵發送提醒通知給尚未提交作業的學生
   - 支援多種通知方式（應用內通知、郵件、短信等）

---

## 2. 數據模型設計

### 2.1 新增數據表

#### 2.1.1 `assignment_distributions` 表

用於記錄作業分配關係，支援按年級、班級或個別學生分配。

```ruby
# Migration: db/migrate/YYYYMMDDHHMMSS_create_assignment_distributions.rb
class CreateAssignmentDistributions < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_distributions, id: :uuid do |t|
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.references :school_academic_year, null: false, foreign_key: true, type: :uuid
      t.references :school, null: false, foreign_key: true, type: :uuid
      
      # 分配類型：class_name（班級）、grade（年級）、individual（個別學生）
      t.string :distribution_type, null: false
      
      # 分配目標：班級名稱、年級名稱或學生ID
      t.string :target_class_name
      t.string :target_grade
      t.references :target_student, foreign_key: { to_table: :general_users }, type: :uuid
      
      # 截止日期
      t.datetime :deadline, null: true
      
      # 狀態
      t.integer :status, default: 0 # active, cancelled
      
      # 元數據（可擴展）
      t.jsonb :meta, default: {}, null: false
      
      t.timestamps
    end

    add_index :assignment_distributions, [:essay_assignment_id, :school_academic_year_id], 
              name: 'index_assignment_distributions_on_assignment_and_year'
    add_index :assignment_distributions, [:distribution_type, :target_class_name], 
              name: 'index_assignment_distributions_on_type_and_class'
    add_index :assignment_distributions, :target_student_id
    add_index :assignment_distributions, :deadline
    add_index :assignment_distributions, :status
  end
end
```

#### 2.1.2 `assignment_student_assignments` 表

用於記錄具體的學生-作業分配關係，由 `assignment_distributions` 自動生成。

```ruby
# Migration: db/migrate/YYYYMMDDHHMMSS_create_assignment_student_assignments.rb
class CreateAssignmentStudentAssignments < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_student_assignments, id: :uuid do |t|
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      t.references :assignment_distribution, null: false, foreign_key: true, type: :uuid
      
      # 分配狀態
      t.integer :status, default: 0 # assigned, completed, overdue
      
      # 截止日期（從 distribution 複製，但可個別調整）
      t.datetime :deadline, null: true
      
      # 完成時間
      t.datetime :completed_at, null: true
      
      # 元數據
      t.jsonb :meta, default: {}, null: false
      
      t.timestamps
    end

    add_index :assignment_student_assignments, [:essay_assignment_id, :general_user_id], 
              unique: true, name: 'index_assignment_student_assignments_unique'
    add_index :assignment_student_assignments, [:general_user_id, :status]
    add_index :assignment_student_assignments, :deadline
    add_index :assignment_student_assignments, :status
  end
end
```

#### 2.1.3 `assignment_reminders` 表

用於記錄提醒通知發送歷史。

```ruby
# Migration: db/migrate/YYYYMMDDHHMMSS_create_assignment_reminders.rb
class CreateAssignmentReminders < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_reminders, id: :uuid do |t|
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      t.references :reminder_sender, foreign_key: { to_table: :general_users }, type: :uuid
      
      # 提醒類型
      t.integer :reminder_type, default: 0 # in_app, email, sms
      
      # 提醒狀態
      t.integer :status, default: 0 # pending, sent, failed
      
      # 發送時間
      t.datetime :sent_at, null: true
      
      # 元數據
      t.jsonb :meta, default: {}, null: false
      
      t.timestamps
    end

    add_index :assignment_reminders, [:essay_assignment_id, :general_user_id]
    add_index :assignment_reminders, :status
    add_index :assignment_reminders, :reminder_type
  end
end
```

### 2.2 擴展現有模型

#### 2.2.1 `EssayAssignment` 模型擴展

在 `app/models/essay_assignment.rb` 中添加：

```ruby
# 關聯
has_many :assignment_distributions, dependent: :destroy
has_many :assignment_student_assignments, dependent: :destroy
has_many :assigned_students, through: :assignment_student_assignments, source: :general_user

# 方法
def distributed?
  assignment_distributions.active.exists?
end

def assigned_to_student?(student)
  assignment_student_assignments.where(general_user: student).exists?
end

# 獲取所有被分配的學生（去重）
def all_assigned_students
  GeneralUser.where(id: assignment_student_assignments.select(:general_user_id).distinct)
end

# 獲取作業統計
def assignment_statistics
  total = assignment_student_assignments.count
  completed = assignment_student_assignments.completed.count
  pending = assignment_student_assignments.assigned.count
  overdue = assignment_student_assignments.overdue.count
  
  {
    total: total,
    completed: completed,
    pending: pending,
    overdue: overdue,
    completion_rate: total.zero? ? 0.0 : (completed.to_f / total * 100).round(2)
  }
end
```

#### 2.2.2 `GeneralUser` 模型擴展

在 `app/models/general_user.rb` 中添加：

```ruby
# 關聯
has_many :assignment_student_assignments, dependent: :destroy
has_many :assigned_essay_assignments, through: :assignment_student_assignments, source: :essay_assignment

# 方法
def pending_assignments
  assigned_essay_assignments
    .joins(:assignment_student_assignments)
    .where(assignment_student_assignments: { 
      general_user_id: id, 
      status: [:assigned, :overdue] 
    })
    .where('assignment_student_assignments.deadline > ? OR assignment_student_assignments.deadline IS NULL', Time.current)
end

def overdue_assignments
  assigned_essay_assignments
    .joins(:assignment_student_assignments)
    .where(assignment_student_assignments: { 
      general_user_id: id, 
      status: :overdue 
    })
    .where('assignment_student_assignments.deadline < ?', Time.current)
end

def completed_assignments
  assigned_essay_assignments
    .joins(:assignment_student_assignments)
    .where(assignment_student_assignments: { 
      general_user_id: id, 
      status: :completed 
    })
end

# 獲取所有分配的作業（包括狀態信息）
def my_assignments(status: nil)
  query = assignment_student_assignments
            .includes(:essay_assignment)
            .order('assignment_student_assignments.created_at DESC')
  
  query = query.where(status: status) if status.present?
  query
end
```

---

## 3. 模型實現

### 3.1 `AssignmentDistribution` 模型

```ruby
# app/models/assignment_distribution.rb
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
    grade: 'grade',              # 按年級分配
    individual: 'individual'      # 按個別學生分配
  }

  validates :distribution_type, presence: true
  validates :deadline, presence: true
  validate :target_must_be_present
  validate :target_must_be_in_current_school_and_year
  validate :deadline_after_creation

  after_create :create_student_assignments
  after_update :update_student_assignments, if: :saved_change_to_deadline?

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
    when 'grade'
      # 假設年級信息存儲在 class_name 的前綴（如 "1A", "1B" 中的 "1"）
      # 或可以從 meta 中獲取
      StudentEnrollment
        .joins(:school_academic_year)
        .where(school_academic_years: { id: school_academic_year_id })
        .where("class_name LIKE ? OR meta->>'grade' = ?", "#{target_grade}%", target_grade)
        .where(status: :active)
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
    when 'grade'
      errors.add(:target_grade, '年級不能為空') if target_grade.blank?
    when 'individual'
      errors.add(:target_student_id, '學生不能為空') if target_student_id.blank?
    end
  end

  def target_must_be_in_current_school_and_year
    return unless school_academic_year

    case distribution_type
    when 'class_name', 'grade'
      # 驗證班級或年級是否存在於當前學年
      enrollment_count = StudentEnrollment
        .joins(:school_academic_year)
        .where(school_academic_years: { id: school_academic_year_id })
        .where(status: :active)
        .count

      if enrollment_count.zero?
        errors.add(:base, '指定的班級或年級在當前學年中沒有學生')
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

    errors.add(:deadline, '截止日期必須在創建時間之後') if deadline <= created_at
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
    AssignmentStudentAssignment.import(assignments, validate: true, on_duplicate_key_ignore: true)
    
    # 觸發通知（異步處理）
    AssignmentDistributionNotificationJob.perform_async(id)
  end

  def update_student_assignments
    assignment_student_assignments
      .where(status: [:assigned, :overdue])
      .update_all(deadline: deadline, updated_at: Time.current)
  end
end
```

### 3.2 `AssignmentStudentAssignment` 模型

```ruby
# app/models/assignment_student_assignment.rb
# frozen_string_literal: true

class AssignmentStudentAssignment < ApplicationRecord
  belongs_to :essay_assignment
  belongs_to :general_user
  belongs_to :assignment_distribution

  enum status: {
    assigned: 0,    # 已分配，未完成
    completed: 1,   # 已完成
    overdue: 2      # 已逾期
  }

  validates :essay_assignment_id, uniqueness: { 
    scope: :general_user_id,
    message: '該作業已經分配給該學生'
  }

  before_save :update_status_based_on_submission
  after_create :check_and_update_overdue_status

  # 檢查是否有對應的 EssayGrading 記錄
  def has_submission?
    essay_grading.present? && essay_grading.status != 'draft'
  end

  def essay_grading
    @essay_grading ||= EssayGrading.find_by(
      essay_assignment_id: essay_assignment_id,
      general_user_id: general_user_id
    )
  end

  # 更新狀態基於提交情況
  def update_status_based_on_submission
    if has_submission?
      self.status = :completed
      self.completed_at ||= essay_grading.created_at
    elsif deadline.present? && deadline < Time.current && status != :completed
      self.status = :overdue
    end
  end

  # 檢查並更新逾期狀態
  def check_and_update_overdue_status
    return unless deadline.present?
    return if status == :completed

    if deadline < Time.current && !has_submission?
      update_columns(status: AssignmentStudentAssignment.statuses[:overdue])
    end
  end

  # 定期任務：更新所有逾期狀態
  def self.update_overdue_statuses
    where(status: [:assigned])
      .where('deadline < ?', Time.current)
      .where.not(
        id: EssayGrading
          .where.not(status: 'draft')
          .select("CONCAT(essay_assignment_id, '-', general_user_id)")
      )
      .update_all(status: AssignmentStudentAssignment.statuses[:overdue])
  end

  # 計算剩餘天數
  def days_remaining
    return nil unless deadline.present?
    
    days = ((deadline - Time.current) / 1.day).ceil
    days.positive? ? days : 0
  end

  # 是否逾期
  def overdue?
    return false unless deadline.present?
    deadline < Time.current && !has_submission?
  end
end
```

### 3.3 EssayGradingsController 修改說明

**重要**：需要修改 `app/controllers/api/v1/essay_gradings_controller.rb` 的 `create` 方法，以支持兩種作業提交方式：

1. **通過分配的作業進入**：學生從「我的作業」列表進入，此時應該有對應的 `AssignmentStudentAssignment` 記錄
2. **直接通過 code 進入**：學生直接輸入作業 code 進入，此時可能沒有分配記錄

**實現邏輯**：
- 在保存 `EssayGrading` 後，檢查是否存在對應的 `AssignmentStudentAssignment`
- 如果存在，說明是通過分配的作業進入，需要更新分配狀態為 `completed`
- 如果不存在，說明是直接通過 code 進入，不需要更新分配狀態

**修改示例**：

```ruby
# 在 EssayGradingsController#create 方法中
if @essay_grading.save
  # 檢查是否有對應的作業分配，如果有則更新分配狀態
  # 只有非草稿狀態的提交才更新分配狀態
  update_assignment_status_if_needed unless @essay_grading.status == 'draft'
  
  render json: { success: true, essay_grading: @essay_grading }, status: :created
else
  render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
end

private

# 更新作業分配狀態（如果存在對應的分配記錄）
def update_assignment_status_if_needed
  assignment = AssignmentStudentAssignment.find_by(
    essay_assignment_id: @essay_assignment.id,
    general_user_id: current_general_user.id
  )

  if assignment
    assignment.update_columns(
      status: AssignmentStudentAssignment.statuses[:completed],
      completed_at: @essay_grading.created_at
    )
  end
end
```

詳細實現請參考「任務 3」文檔。

### 3.4 `AssignmentReminder` 模型

```ruby
# app/models/assignment_reminder.rb
# frozen_string_literal: true

class AssignmentReminder < ApplicationRecord
  belongs_to :essay_assignment
  belongs_to :general_user
  belongs_to :reminder_sender, class_name: 'GeneralUser', optional: true

  enum reminder_type: {
    in_app: 0,
    email: 1,
    sms: 2
  }

  enum status: {
    pending: 0,
    sent: 1,
    failed: 2
  }

  validates :reminder_type, presence: true

  after_create :send_reminder, if: :pending?

  private

  def send_reminder
    case reminder_type
    when 'in_app'
      send_in_app_notification
    when 'email'
      send_email_notification
    when 'sms'
      send_sms_notification
    end
  end

  def send_in_app_notification
    # 使用 Noticed gem 發送應用內通知
    AssignmentReminderNotifier.with(
      essay_assignment: essay_assignment,
      deadline: assignment_student_assignment&.deadline
    ).deliver(general_user)
    
    update_columns(status: AssignmentReminder.statuses[:sent], sent_at: Time.current)
  rescue StandardError => e
    Rails.logger.error "Failed to send in-app reminder: #{e.message}"
    update_columns(status: AssignmentReminder.statuses[:failed])
  end

  def send_email_notification
    AssignmentReminderMailer.remind_student(
      general_user,
      essay_assignment,
      assignment_student_assignment&.deadline
    ).deliver_later
    
    update_columns(status: AssignmentReminder.statuses[:sent], sent_at: Time.current)
  rescue StandardError => e
    Rails.logger.error "Failed to send email reminder: #{e.message}"
    update_columns(status: AssignmentReminder.statuses[:failed])
  end

  def send_sms_notification
    # 使用現有的 Twilio 通知機制
    message = "提醒：您有作業「#{essay_assignment.title}」尚未提交，截止日期：#{assignment_student_assignment&.deadline&.strftime('%Y-%m-%d %H:%M')}"
    
    AssignmentReminderNotifier.with(
      target_phone_number: general_user.phone,
      message: message
    ).deliver(general_user)
    
    update_columns(status: AssignmentReminder.statuses[:sent], sent_at: Time.current)
  rescue StandardError => e
    Rails.logger.error "Failed to send SMS reminder: #{e.message}"
    update_columns(status: AssignmentReminder.statuses[:failed])
  end

  def assignment_student_assignment
    @assignment_student_assignment ||= AssignmentStudentAssignment.find_by(
      essay_assignment_id: essay_assignment_id,
      general_user_id: general_user_id
    )
  end
end
```

---

## 4. API 接口設計

### 4.1 作業分配相關 API

#### 4.1.1 獲取可分配的班級和學生列表

**端點**: `GET /api/v1/essay_assignments/distribution_options`

**描述**: 獲取當前老師所在學校的當前學年下，可分配的班級、年級和學生列表。

**認證**: 需要 JWT Token，且用戶必須是教師

**查詢參數**:
- `school_academic_year_id` (可選): 指定學年ID，不提供則使用當前活躍學年

**成功響應** (200 OK):
```json
{
  "success": true,
  "options": {
    "school_academic_year": {
      "id": "uuid",
      "name": "2024-2025學年",
      "start_date": "2024-09-01",
      "end_date": "2025-06-30"
    },
    "classes": [
      {
        "class_name": "1A",
        "student_count": 25
      },
      {
        "class_name": "1B",
        "student_count": 23
      }
    ],
    "grades": [
      {
        "grade": "1",
        "student_count": 48
      }
    ],
    "students": [
      {
        "id": "uuid",
        "nickname": "張三",
        "email": "zhang@example.com",
        "class_name": "1A",
        "class_number": "01"
      }
    ]
  }
}
```

#### 4.1.2 創建作業分配

**端點**: `POST /api/v1/essay_assignments/:essay_assignment_id/distributions`

**描述**: 為指定作業創建分配記錄，支援按班級、年級或個別學生分配。

**認證**: 需要 JWT Token，且用戶必須是作業創建者或同校教師

**請求體**:
```json
{
  "distribution": {
    "distribution_type": "class_name",
    "target_class_name": "1A",
    "deadline": "2024-12-31T23:59:59Z",
    "school_academic_year_id": "uuid"
  }
}
```

**批量分配示例**:
```json
{
  "distributions": [
    {
      "distribution_type": "class_name",
      "target_class_name": "1A",
      "deadline": "2024-12-31T23:59:59Z"
    },
    {
      "distribution_type": "grade",
      "target_grade": "2",
      "deadline": "2024-12-31T23:59:59Z"
    },
    {
      "distribution_type": "individual",
      "target_student_id": "uuid",
      "deadline": "2024-12-31T23:59:59Z"
    }
  ]
}
```

**成功響應** (201 Created):
```json
{
  "success": true,
  "distributions": [
    {
      "id": "uuid",
      "distribution_type": "class_name",
      "target_class_name": "1A",
      "deadline": "2024-12-31T23:59:59Z",
      "assigned_students_count": 25,
      "created_at": "2024-01-01T10:00:00Z"
    }
  ]
}
```

#### 4.1.3 獲取作業分配列表

**端點**: `GET /api/v1/essay_assignments/:essay_assignment_id/distributions`

**描述**: 獲取指定作業的所有分配記錄。

**成功響應** (200 OK):
```json
{
  "success": true,
  "distributions": [
    {
      "id": "uuid",
      "distribution_type": "class_name",
      "target_class_name": "1A",
      "deadline": "2024-12-31T23:59:59Z",
      "assigned_students_count": 25,
      "status": "active"
    }
  ]
}
```

### 4.2 學生作業列表 API

#### 4.2.1 獲取學生的作業列表

**端點**: `GET /api/v1/essay_assignments/my_assignments`

**描述**: 獲取當前登入學生的所有作業列表，包括待完成、進行中、已完成和已逾期。

**認證**: 需要 JWT Token，且用戶必須是學生

**查詢參數**:
- `status` (可選): 過濾狀態，可選值：`assigned`, `completed`, `overdue`
- `page` (可選): 頁碼，默認 1
- `per_page` (可選): 每頁數量，默認 25

**成功響應** (200 OK):
```json
{
  "success": true,
  "assignments": [
    {
      "id": "uuid",
      "essay_assignment": {
        "id": "uuid",
        "title": "作業標題",
        "topic": "作業主題",
        "category": "essay",
        "code": "abc123"
      },
      "status": "assigned",
      "deadline": "2024-12-31T23:59:59Z",
      "is_overdue": false,
      "days_remaining": 30,
      "has_submission": false,
      "created_at": "2024-01-01T10:00:00Z"
    }
  ],
  "meta": {
    "pagination": {
      "current_page": 1,
      "next_page": 2,
      "prev_page": null,
      "total_pages": 5,
      "total_count": 48
    },
    "statistics": {
      "assigned_count": 10,
      "completed_count": 30,
      "overdue_count": 8
    }
  }
}
```

### 4.3 作業統計 API

#### 4.3.1 獲取作業完成情況統計

**端點**: `GET /api/v1/essay_assignments/:essay_assignment_id/statistics`

**描述**: 獲取指定作業的完成情況統計，包括各學生的提交狀態。

**認證**: 需要 JWT Token，且用戶必須是作業創建者或同校教師

**查詢參數**:
- `class_name` (可選): 按班級過濾
- `status` (可選): 按狀態過濾：`assigned`, `completed`, `overdue`
- `page` (可選): 頁碼
- `per_page` (可選): 每頁數量

**成功響應** (200 OK):
```json
{
  "success": true,
  "statistics": {
    "total_assigned": 50,
    "completed_count": 30,
    "pending_count": 12,
    "overdue_count": 8,
    "completion_rate": 60.0,
    "by_class": [
      {
        "class_name": "1A",
        "total": 25,
        "completed": 15,
        "pending": 7,
        "overdue": 3
      }
    ],
    "students": [
      {
        "student_id": "uuid",
        "student_name": "張三",
        "class_name": "1A",
        "class_number": "01",
        "status": "completed",
        "submitted_at": "2024-01-15T10:00:00Z",
        "deadline": "2024-12-31T23:59:59Z"
      }
    ]
  },
  "meta": {
    "pagination": {
      "current_page": 1,
      "total_pages": 2,
      "total_count": 50
    }
  }
}
```

### 4.4 提醒通知 API

#### 4.4.1 發送提醒通知

**端點**: `POST /api/v1/essay_assignments/:essay_assignment_id/send_reminders`

**描述**: 向未完成作業的學生發送提醒通知。

**認證**: 需要 JWT Token，且用戶必須是作業創建者或同校教師

**請求體**:
```json
{
  "reminder": {
    "reminder_type": "in_app",
    "target_students": ["uuid1", "uuid2"],
    "message": "自定義提醒訊息"
  }
}
```

**成功響應** (200 OK):
```json
{
  "success": true,
  "reminders_sent": 15,
  "reminders": [
    {
      "id": "uuid",
      "student_id": "uuid",
      "student_name": "張三",
      "reminder_type": "in_app",
      "status": "sent",
      "sent_at": "2024-01-20T10:00:00Z"
    }
  ]
}
```

---

## 5. 控制器實現

### 5.1 `AssignmentDistributionsController`

```ruby
# app/controllers/api/v1/assignment_distributions_controller.rb
# frozen_string_literal: true

module Api
  module V1
    class AssignmentDistributionsController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment
      before_action :ensure_teacher_and_same_school
      before_action :set_distribution, only: %i[show update destroy]

      # GET /api/v1/essay_assignments/distribution_options
      def distribution_options
        school = current_general_user.get_school
        return render_unauthorized unless school

        academic_year = params[:school_academic_year_id].present? ? 
          SchoolAcademicYear.find_by(id: params[:school_academic_year_id]) :
          school.current_academic_year

        return render_not_found('Academic year not found') unless academic_year

        # 獲取班級列表
        classes = StudentEnrollment
          .joins(:school_academic_year)
          .where(school_academic_years: { id: academic_year.id })
          .where(status: :active)
          .group(:class_name)
          .select('class_name, COUNT(*) as student_count')
          .map { |e| { class_name: e.class_name, student_count: e.student_count } }

        # 獲取年級列表（從班級名稱提取）
        grades = StudentEnrollment
          .joins(:school_academic_year)
          .where(school_academic_years: { id: academic_year.id })
          .where(status: :active)
          .select("SUBSTRING(class_name FROM '^[0-9]+') as grade, COUNT(*) as student_count")
          .group("SUBSTRING(class_name FROM '^[0-9]+')")
          .map { |e| { grade: e.grade, student_count: e.student_count } }
          .compact

        # 獲取學生列表
        students = GeneralUser
          .joins(:student_enrollments)
          .where(student_enrollments: { 
            school_academic_year_id: academic_year.id,
            status: :active 
          })
          .select(:id, :nickname, :email, :class_no)
          .map do |user|
            enrollment = user.current_enrollment
            {
              id: user.id,
              nickname: user.nickname,
              email: user.email,
              class_name: enrollment&.class_name,
              class_number: user.class_no
            }
          end

        render json: {
          success: true,
          options: {
            school_academic_year: {
              id: academic_year.id,
              name: academic_year.name,
              start_date: academic_year.start_date,
              end_date: academic_year.end_date
            },
            classes: classes,
            grades: grades,
            students: students
          }
        }, status: :ok
      end

      # POST /api/v1/essay_assignments/:essay_assignment_id/distributions
      def create
        school = current_general_user.get_school
        academic_year = school&.current_academic_year

        return render_not_found('School or academic year not found') unless school && academic_year

        # 支援批量創建
        if params[:distributions].present?
          distributions = params[:distributions].map do |dist_params|
            distribution = @essay_assignment.assignment_distributions.build(
              distribution_params(dist_params)
            )
            distribution.school = school
            distribution.school_academic_year = academic_year
            distribution
          end

          saved = distributions.select(&:save)
          failed = distributions.reject(&:persisted?)

          render json: {
            success: failed.empty?,
            distributions: saved.map { |d| distribution_json(d) },
            errors: failed.map { |d| d.errors.full_messages }
          }, status: failed.empty? ? :created : :unprocessable_entity
        else
          distribution = @essay_assignment.assignment_distributions.build(distribution_params)
          distribution.school = school
          distribution.school_academic_year = academic_year

          if distribution.save
            render json: {
              success: true,
              distribution: distribution_json(distribution)
            }, status: :created
          else
            render json: {
              success: false,
              errors: distribution.errors.full_messages
            }, status: :unprocessable_entity
          end
        end
      end

      # GET /api/v1/essay_assignments/:essay_assignment_id/distributions
      def index
        distributions = @essay_assignment.assignment_distributions
                                          .active
                                          .includes(:school_academic_year)
                                          .order(created_at: :desc)

        render json: {
          success: true,
          distributions: distributions.map { |d| distribution_json(d) }
        }, status: :ok
      end

      # GET /api/v1/essay_assignments/:essay_assignment_id/distributions/:id
      def show
        render json: {
          success: true,
          distribution: distribution_json(@distribution, include_students: true)
        }, status: :ok
      end

      # PATCH /api/v1/essay_assignments/:essay_assignment_id/distributions/:id
      def update
        if @distribution.update(distribution_params)
          render json: {
            success: true,
            distribution: distribution_json(@distribution)
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @distribution.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      # DELETE /api/v1/essay_assignments/:essay_assignment_id/distributions/:id
      def destroy
        if @distribution.cancelled!
          render json: {
            success: true,
            message: 'Distribution cancelled successfully'
          }, status: :ok
        else
          render json: {
            success: false,
            errors: @distribution.errors.full_messages
          }, status: :unprocessable_entity
        end
      end

      private

      def set_essay_assignment
        @essay_assignment = EssayAssignment.find(params[:essay_assignment_id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def set_distribution
        @distribution = @essay_assignment.assignment_distributions.find(params[:id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'Distribution not found' }, status: :not_found
      end

      def ensure_teacher_and_same_school
        unless current_general_user.aienglish_role == 'teacher'
          render json: { success: false, error: 'Only teachers can manage distributions' }, 
                 status: :forbidden
          return
        end

        school = current_general_user.get_school
        unless school && @essay_assignment.general_user.get_school&.id == school.id
          render json: { success: false, error: 'You can only manage distributions in your own school' }, 
                 status: :forbidden
        end
      end

      def distribution_params(params_hash = nil)
        params_to_use = params_hash || params[:distribution] || {}
        params_to_use.permit(
          :distribution_type,
          :target_class_name,
          :target_grade,
          :target_student_id,
          :deadline,
          :school_academic_year_id
        )
      end

      def distribution_json(distribution, include_students: false)
        json = {
          id: distribution.id,
          distribution_type: distribution.distribution_type,
          target_class_name: distribution.target_class_name,
          target_grade: distribution.target_grade,
          target_student_id: distribution.target_student_id,
          deadline: distribution.deadline&.iso8601,
          status: distribution.status,
          assigned_students_count: distribution.assignment_student_assignments.count,
          created_at: distribution.created_at.iso8601,
          updated_at: distribution.updated_at.iso8601
        }

        if include_students
          json[:assigned_students] = distribution.target_students.map do |student|
            {
              id: student.id,
              nickname: student.nickname,
              email: student.email,
              class_name: student.current_enrollment&.class_name,
              class_number: student.class_no
            }
          end
        end

        json
      end

      def render_unauthorized
        render json: { success: false, error: 'Unauthorized' }, status: :unauthorized
      end

      def render_not_found(message = 'Resource not found')
        render json: { success: false, error: message }, status: :not_found
      end
    end
  end
end
```

### 5.2 `MyAssignmentsController`

```ruby
# app/controllers/api/v1/my_assignments_controller.rb
# frozen_string_literal: true

module Api
  module V1
    class MyAssignmentsController < ApiController
      before_action :authenticate_general_user!
      before_action :ensure_student

      # GET /api/v1/essay_assignments/my_assignments
      def index
        assignments = current_general_user.my_assignments(status: params[:status])
                                          .includes(:essay_assignment)
                                          .order('assignment_student_assignments.created_at DESC')

        # 分頁
        assignments = Kaminari.paginate_array(assignments.to_a).page(params[:page] || 1)
                                                               .per(params[:per_page] || 25)

        assignments_data = assignments.map do |assignment|
          assignment_json(assignment)
        end

        # 統計信息
        all_assignments = current_general_user.my_assignments
        statistics = {
          assigned_count: all_assignments.assigned.count,
          completed_count: all_assignments.completed.count,
          overdue_count: all_assignments.overdue.count
        }

        render json: {
          success: true,
          assignments: assignments_data,
          meta: {
            pagination: {
              current_page: assignments.current_page,
              next_page: assignments.next_page,
              prev_page: assignments.prev_page,
              total_pages: assignments.total_pages,
              total_count: assignments.total_count
            },
            statistics: statistics
          }
        }, status: :ok
      end

      private

      def ensure_student
        unless current_general_user.aienglish_role == 'student'
          render json: { success: false, error: 'Only students can view their assignments' }, 
                 status: :forbidden
        end
      end

      def assignment_json(assignment)
        essay_assignment = assignment.essay_assignment
        {
          id: assignment.id,
          essay_assignment: {
            id: essay_assignment.id,
            title: essay_assignment.title,
            topic: essay_assignment.topic,
            category: essay_assignment.category,
            code: essay_assignment.code
          },
          status: assignment.status,
          deadline: assignment.deadline&.iso8601,
          is_overdue: assignment.overdue?,
          days_remaining: assignment.days_remaining,
          has_submission: assignment.has_submission?,
          completed_at: assignment.completed_at&.iso8601,
          created_at: assignment.created_at.iso8601,
          updated_at: assignment.updated_at.iso8601
        }
      end
    end
  end
end
```

### 5.3 `AssignmentStatisticsController`

```ruby
# app/controllers/api/v1/assignment_statistics_controller.rb
# frozen_string_literal: true

module Api
  module V1
    class AssignmentStatisticsController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment
      before_action :ensure_teacher_and_same_school

      # GET /api/v1/essay_assignments/:essay_assignment_id/statistics
      def show
        statistics_service = AssignmentStatisticsService.new(@essay_assignment)
        statistics = statistics_service.calculate(
          class_name: params[:class_name],
          status: params[:status]
        )

        # 學生列表（分頁）
        students_query = statistics_service.students_query(
          class_name: params[:class_name],
          status: params[:status]
        )

        students = Kaminari.paginate_array(students_query.to_a)
                          .page(params[:page] || 1)
                          .per(params[:per_page] || 25)

        students_data = students.map do |student_assignment|
          student = student_assignment.general_user
          enrollment = student.current_enrollment
          
          {
            student_id: student.id,
            student_name: student.nickname,
            student_email: student.email,
            class_name: enrollment&.class_name,
            class_number: student.class_no,
            status: student_assignment.status,
            submitted_at: student_assignment.completed_at&.iso8601,
            deadline: student_assignment.deadline&.iso8601,
            is_overdue: student_assignment.overdue?
          }
        end

        render json: {
          success: true,
          statistics: statistics.merge(
            students: students_data
          ),
          meta: {
            pagination: {
              current_page: students.current_page,
              next_page: students.next_page,
              prev_page: students.prev_page,
              total_pages: students.total_pages,
              total_count: students.total_count
            }
          }
        }, status: :ok
      end

      private

      def set_essay_assignment
        @essay_assignment = EssayAssignment.find(params[:essay_assignment_id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def ensure_teacher_and_same_school
        unless current_general_user.aienglish_role == 'teacher'
          render json: { success: false, error: 'Only teachers can view statistics' }, 
                 status: :forbidden
          return
        end

        school = current_general_user.get_school
        unless school && @essay_assignment.general_user.get_school&.id == school.id
          render json: { success: false, error: 'You can only view statistics for assignments in your own school' }, 
                 status: :forbidden
        end
      end
    end
  end
end
```

### 5.4 `AssignmentRemindersController`

```ruby
# app/controllers/api/v1/assignment_reminders_controller.rb
# frozen_string_literal: true

module Api
  module V1
    class AssignmentRemindersController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment
      before_action :ensure_teacher_and_same_school

      # POST /api/v1/essay_assignments/:essay_assignment_id/send_reminders
      def create
        reminder_service = AssignmentReminderService.new(
          @essay_assignment,
          current_general_user
        )

        result = reminder_service.send_reminders(
          reminder_type: reminder_params[:reminder_type] || 'in_app',
          target_students: reminder_params[:target_students],
          message: reminder_params[:message]
        )

        if result.success?
          render json: {
            success: true,
            reminders_sent: result.reminders_sent,
            reminders: result.reminders.map { |r| reminder_json(r) }
          }, status: :ok
        else
          render json: {
            success: false,
            error: result.error_message
          }, status: :unprocessable_entity
        end
      end

      private

      def set_essay_assignment
        @essay_assignment = EssayAssignment.find(params[:essay_assignment_id])
      rescue ActiveRecord::RecordNotFound
        render json: { success: false, error: 'EssayAssignment not found' }, status: :not_found
      end

      def ensure_teacher_and_same_school
        unless current_general_user.aienglish_role == 'teacher'
          render json: { success: false, error: 'Only teachers can send reminders' }, 
                 status: :forbidden
          return
        end

        school = current_general_user.get_school
        unless school && @essay_assignment.general_user.get_school&.id == school.id
          render json: { success: false, error: 'You can only send reminders for assignments in your own school' }, 
                 status: :forbidden
        end
      end

      def reminder_params
        params.require(:reminder).permit(:reminder_type, :message, target_students: [])
      end

      def reminder_json(reminder)
        {
          id: reminder.id,
          student_id: reminder.general_user_id,
          student_name: reminder.general_user.nickname,
          reminder_type: reminder.reminder_type,
          status: reminder.status,
          sent_at: reminder.sent_at&.iso8601,
          created_at: reminder.created_at.iso8601
        }
      end
    end
  end
end
```

---

## 6. 服務對象實現

### 6.1 `AssignmentStatisticsService`

```ruby
# app/services/assignment_statistics_service.rb
# frozen_string_literal: true

class AssignmentStatisticsService
  def initialize(essay_assignment)
    @essay_assignment = essay_assignment
  end

  def calculate(class_name: nil, status: nil)
    query = @essay_assignment.assignment_student_assignments

    # 按班級過濾
    if class_name.present?
      query = query.joins(:general_user)
                   .joins('INNER JOIN student_enrollments ON student_enrollments.general_user_id = general_users.id')
                   .where(student_enrollments: { class_name: class_name, status: :active })
    end

    # 按狀態過濾
    query = query.where(status: status) if status.present?

    total = query.count
    completed = query.completed.count
    pending = query.assigned.count
    overdue = query.overdue.count

    # 按班級統計
    by_class = calculate_by_class(query)

    {
      total_assigned: total,
      completed_count: completed,
      pending_count: pending,
      overdue_count: overdue,
      completion_rate: total.zero? ? 0.0 : (completed.to_f / total * 100).round(2),
      by_class: by_class
    }
  end

  def students_query(class_name: nil, status: nil)
    query = @essay_assignment.assignment_student_assignments
                             .includes(:general_user)

    if class_name.present?
      query = query.joins(:general_user)
                   .joins('INNER JOIN student_enrollments ON student_enrollments.general_user_id = general_users.id')
                   .where(student_enrollments: { class_name: class_name, status: :active })
    end

    query = query.where(status: status) if status.present?

    query.order('general_users.nickname ASC')
  end

  private

  def calculate_by_class(base_query)
    StudentEnrollment
      .joins(:general_user)
      .where(general_user_id: base_query.select(:general_user_id))
      .where(status: :active)
      .group(:class_name)
      .select('class_name, COUNT(*) as total')
      .map do |enrollment|
        class_name = enrollment.class_name
        class_assignments = base_query.joins(:general_user)
                                     .joins('INNER JOIN student_enrollments ON student_enrollments.general_user_id = general_users.id')
                                     .where(student_enrollments: { class_name: class_name, status: :active })

        {
          class_name: class_name,
          total: class_assignments.count,
          completed: class_assignments.completed.count,
          pending: class_assignments.assigned.count,
          overdue: class_assignments.overdue.count
        }
      end
  end
end
```

### 6.2 `AssignmentReminderService`

```ruby
# app/services/assignment_reminder_service.rb
# frozen_string_literal: true

class AssignmentReminderService
  Result = Struct.new(:success?, :reminders_sent, :reminders, :error_message, keyword_init: true)

  def initialize(essay_assignment, sender)
    @essay_assignment = essay_assignment
    @sender = sender
  end

  def send_reminders(reminder_type:, target_students: nil, message: nil)
    # 獲取需要發送提醒的學生
    students_to_remind = target_students.present? ? 
      GeneralUser.where(id: target_students) :
      @essay_assignment.assignment_student_assignments
                      .where(status: [:assigned, :overdue])
                      .includes(:general_user)
                      .map(&:general_user)

    return Result.new(success?: false, error_message: 'No students to remind') if students_to_remind.empty?

    reminders = []
    students_to_remind.each do |student|
      reminder = AssignmentReminder.create!(
        essay_assignment: @essay_assignment,
        general_user: student,
        reminder_sender: @sender,
        reminder_type: reminder_type,
        meta: { message: message }
      )
      reminders << reminder
    rescue StandardError => e
      Rails.logger.error "Failed to create reminder for student #{student.id}: #{e.message}"
    end

    Result.new(
      success?: true,
      reminders_sent: reminders.count { |r| r.status == 'sent' },
      reminders: reminders
    )
  end
end
```

---

## 7. 後台任務實現

### 7.1 `AssignmentDistributionNotificationJob`

```ruby
# app/sidekiq/assignment_distribution_notification_job.rb
# frozen_string_literal: true

class AssignmentDistributionNotificationJob
  include Sidekiq::Job

  sidekiq_options queue: :notifications, retry: 3

  def perform(distribution_id)
    distribution = AssignmentDistribution.find(distribution_id)
    return unless distribution.active?

    students = distribution.target_students
    return if students.empty?

    # 發送應用內通知給所有被分配的學生
    students.each do |student|
      AssignmentDistributionNotifier.with(
        essay_assignment: distribution.essay_assignment,
        deadline: distribution.deadline
      ).deliver_later(student)
    end

    Rails.logger.info "Sent distribution notifications to #{students.count} students for assignment #{distribution.essay_assignment_id}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "AssignmentDistribution not found: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Failed to send distribution notifications: #{e.message}"
    raise e
  end
end
```

### 7.2 `UpdateOverdueAssignmentsJob`

```ruby
# app/sidekiq/update_overdue_assignments_job.rb
# frozen_string_literal: true

class UpdateOverdueAssignmentsJob
  include Sidekiq::Job

  sidekiq_options queue: :default, retry: 2

  # 定期更新所有逾期狀態的作業
  def perform
    updated_count = AssignmentStudentAssignment.update_overdue_statuses
    Rails.logger.info "Updated #{updated_count} assignments to overdue status"
  end
end
```

---

## 8. 通知器和郵件器實現

### 8.1 `AssignmentReminderNotifier`

```ruby
# app/notifiers/assignment_reminder_notifier.rb
# frozen_string_literal: true

class AssignmentReminderNotifier < Noticed::Event
  required_params :essay_assignment, :deadline

  deliver_by :database
  deliver_by :email, mailer: 'AssignmentReminderMailer', method: :remind_student, if: :email_delivery?

  def email_delivery?
    params[:reminder_type] == 'email' || params[:reminder_type].nil?
  end

  def message
    "您有作業「#{params[:essay_assignment].title}」尚未提交"
  end

  def url
    "/assignments/#{params[:essay_assignment].code}"
  end
end
```

### 8.2 `AssignmentDistributionNotifier`

```ruby
# app/notifiers/assignment_distribution_notifier.rb
# frozen_string_literal: true

class AssignmentDistributionNotifier < Noticed::Event
  required_params :essay_assignment, :deadline

  deliver_by :database
  deliver_by :email, mailer: 'AssignmentDistributionMailer', method: :notify_student

  def message
    "您收到新作業「#{params[:essay_assignment].title}」"
  end

  def url
    "/assignments/#{params[:essay_assignment].code}"
  end
end
```

### 8.3 `AssignmentReminderMailer`

```ruby
# app/mailers/assignment_reminder_mailer.rb
# frozen_string_literal: true

class AssignmentReminderMailer < ApplicationMailer
  def remind_student(student, essay_assignment, deadline)
    @student = student
    @essay_assignment = essay_assignment
    @deadline = deadline
    @days_remaining = deadline.present? ? ((deadline - Time.current) / 1.day).ceil : nil

    mail(
      to: @student.email,
      subject: "作業提醒：#{@essay_assignment.title}"
    )
  end
end
```

### 8.4 `AssignmentDistributionMailer`

```ruby
# app/mailers/assignment_distribution_mailer.rb
# frozen_string_literal: true

class AssignmentDistributionMailer < ApplicationMailer
  def notify_student(student, essay_assignment, deadline)
    @student = student
    @essay_assignment = essay_assignment
    @deadline = deadline
    @days_remaining = deadline.present? ? ((deadline - Time.current) / 1.day).ceil : nil

    mail(
      to: @student.email,
      subject: "新作業通知：#{@essay_assignment.title}"
    )
  end
end
```

---

## 9. 路由配置

在 `config/routes.rb` 中添加：

```ruby
namespace :api do
  namespace :v1 do
    # 作業分配相關路由
    resources :essay_assignments do
      # 獲取分配選項（需要在 resources 外定義，因為是集合路由）
      collection do
        get 'distribution_options', to: 'assignment_distributions#distribution_options'
      end

      # 分配管理
      resources :distributions, controller: 'assignment_distributions', except: [:new, :edit] do
      end

      # 統計
      member do
        get 'statistics', to: 'assignment_statistics#show'
        post 'send_reminders', to: 'assignment_reminders#create'
      end
    end

    # 學生作業列表
    get 'essay_assignments/my_assignments', to: 'my_assignments#index'
  end
end
```

---

## 10. 實現步驟

### 10.1 數據庫遷移

1. **創建遷移文件**：
   ```bash
   rails generate migration CreateAssignmentDistributions
   rails generate migration CreateAssignmentStudentAssignments
   rails generate migration CreateAssignmentReminders
   ```

2. **執行遷移**：
   ```bash
   rake db:migrate
   # 如果是多租戶環境
   rake apartment:migrate
   ```

### 10.2 模型實現

1. 創建模型文件：
   - `app/models/assignment_distribution.rb`
   - `app/models/assignment_student_assignment.rb`
   - `app/models/assignment_reminder.rb`

2. 擴展現有模型：
   - 在 `EssayAssignment` 中添加關聯和方法
   - 在 `GeneralUser` 中添加關聯和方法

### 10.3 控制器實現

1. 創建控制器文件：
   - `app/controllers/api/v1/assignment_distributions_controller.rb`
   - `app/controllers/api/v1/my_assignments_controller.rb`
   - `app/controllers/api/v1/assignment_statistics_controller.rb`
   - `app/controllers/api/v1/assignment_reminders_controller.rb`

### 10.4 服務對象實現

1. 創建服務文件：
   - `app/services/assignment_statistics_service.rb`
   - `app/services/assignment_reminder_service.rb`

### 10.5 後台任務實現

1. 創建 Sidekiq Job：
   - `app/sidekiq/assignment_distribution_notification_job.rb`
   - `app/sidekiq/update_overdue_assignments_job.rb`

2. 配置定時任務（使用 `sidekiq-scheduler` 或 `whenever`）：
   ```ruby
   # config/schedule.rb (使用 whenever)
   every 1.hour do
     runner "UpdateOverdueAssignmentsJob.perform_async"
   end
   ```

### 10.6 通知器和郵件器實現

1. 創建通知器：
   - `app/notifiers/assignment_reminder_notifier.rb`
   - `app/notifiers/assignment_distribution_notifier.rb`

2. 創建郵件器：
   - `app/mailers/assignment_reminder_mailer.rb`
   - `app/mailers/assignment_distribution_mailer.rb`

3. 創建郵件視圖：
   - `app/views/assignment_reminder_mailer/remind_student.html.erb`
   - `app/views/assignment_reminder_mailer/remind_student.text.erb`
   - `app/views/assignment_distribution_mailer/notify_student.html.erb`
   - `app/views/assignment_distribution_mailer/notify_student.text.erb`

### 10.7 路由配置

在 `config/routes.rb` 中添加新路由。

### 10.8 測試

1. **模型測試**：
   - 測試 `AssignmentDistribution` 的驗證和回調
   - 測試 `AssignmentStudentAssignment` 的狀態更新邏輯
   - 測試 `AssignmentReminder` 的通知發送

2. **控制器測試**：
   - 測試所有 API 端點的請求/響應
   - 測試權限驗證
   - 測試錯誤處理

3. **服務測試**：
   - 測試統計計算邏輯
   - 測試提醒發送邏輯

---

## 11. 注意事項

### 11.1 性能優化

1. **批量操作**：使用 `import` gem 進行批量插入，避免 N+1 查詢
2. **索引優化**：確保所有查詢字段都有適當的索引
3. **緩存策略**：對於頻繁查詢的統計數據，考慮使用 Redis 緩存

### 11.2 多租戶支持

1. **租戶隔離**：確保所有查詢都正確過濾租戶數據
2. **遷移執行**：使用 `rake apartment:migrate` 執行租戶遷移

### 11.3 錯誤處理

1. **異常捕獲**：在所有關鍵操作中添加異常處理
2. **日誌記錄**：記錄所有重要操作和錯誤
3. **用戶反饋**：提供清晰的錯誤信息給前端

### 11.4 安全性

1. **權限驗證**：確保只有授權用戶可以執行操作
2. **參數驗證**：使用 Strong Parameters 驗證所有輸入
3. **SQL 注入防護**：使用參數化查詢，避免直接拼接 SQL

---

## 12. 後續優化建議

1. **批量分配優化**：支援 Excel/CSV 導入學生列表進行批量分配
2. **智能提醒**：根據學生歷史完成情況，智能調整提醒頻率
3. **作業模板**：支援保存常用的分配配置作為模板
4. **數據導出**：支援導出統計數據為 Excel/PDF
5. **移動端推送**：整合移動端推送通知（如 Firebase Cloud Messaging）

---

## 13. 總結

本文檔詳細描述了作業自動分派系統的完整實現方案，包括：

- ✅ 數據模型設計（3個新表）
- ✅ 模型實現（3個新模型 + 現有模型擴展）
- ✅ API 接口設計（4個主要端點組）
- ✅ 控制器實現（4個控制器）
- ✅ 服務對象實現（2個服務）
- ✅ 後台任務實現（2個 Job）
- ✅ 通知器和郵件器實現
- ✅ 路由配置
- ✅ 實現步驟
- ✅ 測試建議
- ✅ 注意事項和優化建議

系統實現後，將大大提升作業管理的效率和用戶體驗。