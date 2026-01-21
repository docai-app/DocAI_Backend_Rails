# 任務 5：實現通知功能 API

## 任務目標

實現老師向未完成作業的學生發送提醒通知的功能，僅支援郵件通知方式。

## 任務範圍

1. 實現發送提醒通知的 API
2. 創建提醒服務對象
3. 創建郵件器
4. 實現郵件發送邏輯
5. 返回發送失敗的學生列表

**注意**：後台任務處理分配通知請參考「任務 6」文檔，該任務應在完成其他任務後最後處理。

---

## 1. API 接口

### 1.1 發送提醒通知

**端點**: `POST /api/v1/essay_assignments/:essay_assignment_id/send_reminders`

**描述**: 向未完成作業的學生發送提醒通知。

**認證**: 需要 JWT Token，且用戶必須是作業創建者或同校教師

**請求體**:
```json
{
  "reminder": {
    "target_students": ["uuid1", "uuid2"]
  }
}
```

**參數說明**:
- `target_students` (可選): 目標學生ID數組，不提供則發送給所有未完成學生

**成功響應** (200 OK):
```json
{
  "success": true,
  "reminders_sent": 15,
  "reminders_failed": 2,
  "reminders": [
    {
      "id": "uuid",
      "student_id": "uuid",
      "student_name": "John Doe",
      "student_email": "john@example.com",
      "status": "sent",
      "sent_at": "2024-01-20T10:00:00Z",
      "created_at": "2024-01-20T10:00:00Z"
    }
  ],
  "failed_students": [
    {
      "student_id": "uuid",
      "student_name": "Jane Smith",
      "student_email": "jane@example.com",
      "error": "Email delivery failed"
    }
  ]
}
```

---

## 2. 服務對象實現

### 2.1 `AssignmentReminderService`

**文件**: `app/services/assignment_reminder_service.rb`

```ruby
# frozen_string_literal: true

class AssignmentReminderService
  Result = Struct.new(:success?, :reminders_sent, :reminders_failed, :reminders, :failed_students, :error_message, keyword_init: true)

  def initialize(essay_assignment, sender)
    @essay_assignment = essay_assignment
    @sender = sender
  end

  def send_reminders(target_students: nil)
    # 獲取需要發送提醒的學生
    students_to_remind = if target_students.present?
      GeneralUser.where(id: target_students)
    else
      @essay_assignment.assignment_student_assignments
                      .where(status: [:assigned, :overdue])
                      .includes(:general_user)
                      .map(&:general_user)
    end

    return Result.new(success?: false, error_message: 'No students to remind') if students_to_remind.empty?

    reminders = []
    failed_students = []

    students_to_remind.each do |student|
      reminder = AssignmentReminder.create!(
        essay_assignment: @essay_assignment,
        general_user: student,
        reminder_sender: @sender,
        reminder_type: :email,
        status: :pending
      )
      
      # 發送郵件（異步）
      begin
        assignment = @essay_assignment.assignment_student_assignments
                                      .find_by(general_user_id: student.id)
        deadline = assignment&.deadline

        AssignmentReminderMailer.remind_student(
          student,
          @essay_assignment,
          deadline
        ).deliver_later

        reminder.update_columns(status: AssignmentReminder.statuses[:sent], sent_at: Time.current)
        reminders << reminder
      rescue StandardError => e
        Rails.logger.error "Failed to send email reminder for student #{student.id}: #{e.message}"
        reminder.update_columns(status: AssignmentReminder.statuses[:failed])
        failed_students << {
          student_id: student.id,
          student_name: student.nickname,
          student_email: student.email,
          error: e.message
        }
      end
    rescue StandardError => e
      Rails.logger.error "Failed to create reminder for student #{student.id}: #{e.message}"
      failed_students << {
        student_id: student.id,
        student_name: student.nickname,
        student_email: student.email,
        error: "Failed to create reminder: #{e.message}"
      }
    end

    Result.new(
      success?: true,
      reminders_sent: reminders.count,
      reminders_failed: failed_students.count,
      reminders: reminders,
      failed_students: failed_students
    )
  end
end
```

---

## 3. 控制器實現

### 3.1 `AssignmentRemindersController` 完整實現

**文件**: `app/controllers/api/v1/assignment_reminders_controller.rb`

```ruby
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
          target_students: reminder_params[:target_students]
        )

        if result.success?
          render json: {
            success: true,
            reminders_sent: result.reminders_sent,
            reminders_failed: result.reminders_failed,
            reminders: result.reminders.map { |r| reminder_json(r) },
            failed_students: result.failed_students
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
        params.require(:reminder).permit(target_students: [])
      end

      def reminder_json(reminder)
        {
          id: reminder.id,
          student_id: reminder.general_user_id,
          student_name: reminder.general_user.nickname,
          student_email: reminder.general_user.email,
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

## 4. 郵件器實現

### 4.1 `AssignmentReminderMailer`

**文件**: `app/mailers/assignment_reminder_mailer.rb`

```ruby
# frozen_string_literal: true

class AssignmentReminderMailer < ApplicationMailer
  def remind_student(student, essay_assignment, deadline)
    @student = student
    @essay_assignment = essay_assignment
    @deadline = deadline
    @days_remaining = deadline.present? ? ((deadline - Time.current) / 1.day).ceil : nil

    mail(
      to: @student.email,
      subject: "Assignment Reminder: #{@essay_assignment.title}"
    )
  end
end
```

---

## 5. AssignmentReminder 模型擴展

在 `app/models/assignment_reminder.rb` 中添加通知發送邏輯：

```ruby
# frozen_string_literal: true

class AssignmentReminder < ApplicationRecord
  belongs_to :essay_assignment
  belongs_to :general_user
  belongs_to :reminder_sender, class_name: 'GeneralUser', optional: true

  enum reminder_type: {
    email: 0
  }

  enum status: {
    pending: 0,
    sent: 1,
    failed: 2
  }

  validates :reminder_type, presence: true

  def assignment_student_assignment
    @assignment_student_assignment ||= AssignmentStudentAssignment.find_by(
      essay_assignment_id: essay_assignment_id,
      general_user_id: general_user_id
    )
  end
end
```

---

## 6. 郵件視圖（可選）

如果需要自定義郵件視圖，創建以下文件：

### 7.1 提醒郵件視圖

**文件**: `app/views/assignment_reminder_mailer/remind_student.html.erb`

```erb
<h2>Assignment Reminder</h2>

<p>Dear <%= @student.nickname %>,</p>

<p>You have an assignment "<%= @essay_assignment.title %>" that has not been submitted yet.</p>

<% if @deadline.present? %>
  <p>Deadline: <%= @deadline.strftime('%B %d, %Y at %I:%M %p') %></p>
  <% if @days_remaining.present? && @days_remaining > 0 %>
    <p>Time remaining: <%= @days_remaining %> <%= @days_remaining == 1 ? 'day' : 'days' %></p>
  <% elsif @days_remaining.present? && @days_remaining <= 0 %>
    <p><strong>This assignment is overdue.</strong></p>
  <% end %>
<% end %>

<p><a href="<%= url_for(controller: 'essay_assignments', action: 'show_only', id: @essay_assignment.code) %>">View Assignment Details</a></p>
```

**文件**: `app/views/assignment_reminder_mailer/remind_student.text.erb`

```erb
Assignment Reminder

Dear <%= @student.nickname %>,

You have an assignment "<%= @essay_assignment.title %>" that has not been submitted yet.

<% if @deadline.present? %>
Deadline: <%= @deadline.strftime('%B %d, %Y at %I:%M %p') %>
  <% if @days_remaining.present? && @days_remaining > 0 %>
Time remaining: <%= @days_remaining %> <%= @days_remaining == 1 ? 'day' : 'days' %>
  <% elsif @days_remaining.present? && @days_remaining <= 0 %>
This assignment is overdue.
  <% end %>
<% end %>

View Assignment Details: <%= url_for(controller: 'essay_assignments', action: 'show_only', id: @essay_assignment.code) %>
```

---

## 7. 實現步驟

1. **創建服務對象**：
   - 創建 `AssignmentReminderService` 類
   - 實現 `send_reminders` 方法
   - 實現失敗學生列表的收集和返回

2. **實現控制器**：
   - 實現 `AssignmentRemindersController#create` 方法
   - 調用服務對象發送提醒
   - 返回成功和失敗的學生列表

3. **創建郵件器**：
   - 創建 `AssignmentReminderMailer`
   - 創建郵件視圖（可選）
   - 所有郵件內容使用英文

4. **擴展模型**：
   - 在 `AssignmentReminder` 模型中簡化邏輯，只保留 email 類型

5. **測試功能**：
   - 測試發送郵件通知
   - 測試批量發送
   - 測試指定學生發送
   - 測試返回失敗學生列表
   - 測試郵件內容為英文

**注意**：後台任務處理分配通知請參考「任務 6」文檔，該任務應在完成其他任務後最後處理。

---

## 8. 驗收標準

- [ ] 可以發送郵件通知給未完成作業的學生
- [ ] 支援指定目標學生發送
- [ ] 不指定目標學生時，發送給所有未完成學生
- [ ] 所有通知發送記錄都保存在 `assignment_reminders` 表中
- [ ] 通知狀態正確更新（pending, sent, failed）
- [ ] API 響應包含成功發送的學生列表
- [ ] API 響應包含發送失敗的學生列表及其錯誤信息
- [ ] 所有郵件內容使用英文
- [ ] 所有 API 都有適當的權限驗證
- [ ] 錯誤情況有適當的錯誤處理和日誌記錄

---

## 9. 注意事項

1. **通知方式**：
   - 僅支援郵件通知，使用 ActionMailer
   - 郵件發送使用 `deliver_later` 異步處理

2. **錯誤處理**：
   - 記錄所有發送失敗的通知
   - API 響應必須包含失敗學生列表及其錯誤信息
   - 提供重試機制（通過 Sidekiq）

3. **性能優化**：
   - 批量發送時避免 N+1 查詢
   - 使用 Sidekiq 處理大量通知

4. **郵件內容**：
   - 所有郵件內容必須使用英文
   - 包含作業詳情和截止日期
   - 提供直接鏈接到作業的 URL
   - 如果已逾期，明確標註

5. **後台任務**：
   - 分配通知的後台任務實現請參考「任務 6」文檔
   - 該任務應在完成其他任務後最後處理