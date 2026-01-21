# 任務 6：實現後台任務（最後處理）

## 任務目標

實現定期更新作業逾期狀態的後台任務。

## 任務範圍

1. 創建 `UpdateOverdueAssignmentsJob` 後台任務
2. 創建 `AssignmentDistributionNotificationJob` 後台任務
3. 配置定時任務執行
4. 實現批量更新逾期狀態的邏輯

---

## 1. 後台任務實現

### 1.1 `UpdateOverdueAssignmentsJob`

**文件**: `app/sidekiq/update_overdue_assignments_job.rb`

```ruby
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

## 2. AssignmentStudentAssignment 模型擴展

在 `app/models/assignment_student_assignment.rb` 中添加類方法：

```ruby
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
```

---

## 3. 配置定時任務

### 3.1 使用 `sidekiq-scheduler`

如果使用 `sidekiq-scheduler`，在 `config/sidekiq.yml` 中添加：

```yaml
:schedule:
  update_overdue_assignments:
    cron: '0 * * * *'  # 每小時執行一次
    class: UpdateOverdueAssignmentsJob
```

### 3.2 使用 `whenever`

如果使用 `whenever`，在 `config/schedule.rb` 中添加：

```ruby
every 1.hour do
  runner "UpdateOverdueAssignmentsJob.perform_async"
end
```

---

## 4. 實現步驟

1. **創建後台任務文件**：
   - 創建 `app/sidekiq/update_overdue_assignments_job.rb`
   - 實現 `perform` 方法

2. **擴展模型**：
   - 在 `AssignmentStudentAssignment` 模型中添加 `update_overdue_statuses` 類方法

3. **配置定時任務**：
   - 根據項目使用的定時任務工具（`sidekiq-scheduler` 或 `whenever`）進行配置

4. **測試功能**：
   - 測試後台任務可以正確執行
   - 測試逾期狀態可以正確更新
   - 測試已提交的作業不會被標記為逾期

---

## 5. 驗收標準

- [ ] 後台任務可以正確執行
- [ ] 超過截止日期且未提交的作業，狀態自動更新為 `overdue`
- [ ] 已提交的作業（非草稿）不會被標記為逾期
- [ ] 定期任務使用批量更新，提高效率
- [ ] 任務執行時記錄日誌

---

## 注意事項

1. **執行頻率**：
   - 建議每小時執行一次，避免過於頻繁的數據庫查詢
   - 可以根據實際需求調整執行頻率

2. **性能考慮**：
   - 使用批量更新（`update_all`）提高效率
   - 確保查詢條件正確，避免更新不應該更新的記錄

3. **數據一致性**：
   - 確保只更新真正逾期的作業（已過截止日期且未提交）
   - 已提交的作業（非草稿）不應該被標記為逾期

4. **錯誤處理**：
   - 任務應該有適當的錯誤處理和日誌記錄
   - 考慮任務失敗時的重試機制

---

## 4. 分配通知後台任務實現

### 4.1 `AssignmentDistributionNotificationJob`

**文件**: `app/sidekiq/assignment_distribution_notification_job.rb`

```ruby
# frozen_string_literal: true

class AssignmentDistributionNotificationJob
  include Sidekiq::Job

  sidekiq_options queue: :notifications, retry: 3

  def perform(distribution_id)
    distribution = AssignmentDistribution.find(distribution_id)
    return unless distribution.active?

    students = distribution.target_students
    return if students.empty?

    # 發送郵件通知給所有被分配的學生
    students.each do |student|
      assignment = distribution.essay_assignment.assignment_student_assignments
                               .find_by(general_user_id: student.id)
      deadline = assignment&.deadline || distribution.deadline

      AssignmentReminderMailer.remind_student(
        student,
        distribution.essay_assignment,
        deadline
      ).deliver_later
    end

    Rails.logger.info "Sent distribution email notifications to #{students.count} students for assignment #{distribution.essay_assignment_id}"
  rescue ActiveRecord::RecordNotFound => e
    Rails.logger.error "AssignmentDistribution not found: #{e.message}"
  rescue StandardError => e
    Rails.logger.error "Failed to send distribution notifications: #{e.message}"
    raise e
  end
end
```

### 4.2 在 `AssignmentDistribution` 模型中調用

在 `app/models/assignment_distribution.rb` 中添加回調：

```ruby
after_create :enqueue_distribution_notification

private

def enqueue_distribution_notification
  AssignmentDistributionNotificationJob.perform_async(id)
end
```

---

## 5. 實現步驟

1. **創建後台任務文件**：
   - 創建 `app/sidekiq/update_overdue_assignments_job.rb`
   - 創建 `app/sidekiq/assignment_distribution_notification_job.rb`
   - 實現 `perform` 方法

2. **擴展模型**：
   - 在 `AssignmentStudentAssignment` 模型中添加 `update_overdue_statuses` 類方法
   - 在 `AssignmentDistribution` 模型中添加 `enqueue_distribution_notification` 回調

3. **配置定時任務**：
   - 根據項目使用的定時任務工具（`sidekiq-scheduler` 或 `whenever`）進行配置

4. **測試功能**：
   - 測試後台任務可以正確執行
   - 測試逾期狀態可以正確更新
   - 測試已提交的作業不會被標記為逾期
   - 測試分配通知可以正確發送

---

## 6. 驗收標準

- [ ] 後台任務可以正確執行
- [ ] 超過截止日期且未提交的作業，狀態自動更新為 `overdue`
- [ ] 已提交的作業（非草稿）不會被標記為逾期
- [ ] 定期任務使用批量更新，提高效率
- [ ] 任務執行時記錄日誌
- [ ] 創建分配時自動發送郵件通知給所有被分配的學生
- [ ] 分配通知使用異步處理，不阻塞分配創建流程

---

## 7. 注意事項

1. **執行頻率**：
   - 建議每小時執行一次，避免過於頻繁的數據庫查詢
   - 可以根據實際需求調整執行頻率

2. **性能考慮**：
   - 使用批量更新（`update_all`）提高效率
   - 確保查詢條件正確，避免更新不應該更新的記錄
   - 分配通知使用異步處理，避免阻塞

3. **數據一致性**：
   - 確保只更新真正逾期的作業（已過截止日期且未提交）
   - 已提交的作業（非草稿）不應該被標記為逾期

4. **錯誤處理**：
   - 任務應該有適當的錯誤處理和日誌記錄
   - 考慮任務失敗時的重試機制

5. **通知方式**：
   - 分配通知僅通過郵件發送
   - 所有郵件內容使用英文

---

## 8. 說明

本任務應在完成其他任務後最後處理，因為：
1. 逾期狀態的更新可以在學生提交作業時實時處理
2. 定期任務主要用於處理遺漏的情況
3. 可以先實現核心功能，再添加定期任務作為補充
4. 分配通知可以在分配創建時同步處理，但使用後台任務可以避免阻塞