# 任務 3：實現學生提交作業後分配狀態改變等功能

## 任務目標

實現學生查看作業列表、提交作業後自動更新分配狀態，以及相關的狀態管理功能。

## 任務範圍

1. 實現學生查看自己的作業列表 API
2. 實現學生提交作業後自動更新分配狀態的回調邏輯
3. 擴展 `AssignmentStudentAssignment` 模型的狀態更新邏輯

**注意**：定期更新逾期狀態的後台任務實現請參考「任務 6」文檔，該任務應在完成其他任務後最後處理。

---

## 1. API 接口

### 1.1 獲取學生的作業列表

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
      "completed_at": null,
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

---

## 2. 控制器實現

### 2.1 `MyAssignmentsController` 完整實現

**文件**: `app/controllers/api/v1/my_assignments_controller.rb`

```ruby
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

---

## 3. 模型狀態更新邏輯

### 3.1 `AssignmentStudentAssignment` 模型擴展

在 `app/models/assignment_student_assignment.rb` 中添加狀態更新邏輯：

```ruby
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

---

## 4. EssayGradingsController 修改

### 4.1 修改 `create` 方法

在 `app/controllers/api/v1/essay_gradings_controller.rb` 的 `create` 方法中添加分配狀態更新邏輯：

**重要說明**：
- 學生可以通過兩種方式提交作業：
  1. **通過分配的作業進入**：學生從「我的作業」列表進入，此時應該有對應的 `AssignmentStudentAssignment` 記錄
  2. **直接通過 code 進入**：學生直接輸入作業 code 進入，此時可能沒有分配記錄

**實現邏輯**：
- 在保存 `EssayGrading` 後，檢查是否存在對應的 `AssignmentStudentAssignment`
- 如果存在，說明是通過分配的作業進入，需要更新分配狀態
- 如果不存在，說明是直接通過 code 進入，不需要更新分配狀態

```ruby
def create
  set_essay_assignment_by_code

  @essay_grading = @essay_assignment.essay_gradings.new(essay_grading_params)
  @essay_grading.general_user = current_general_user
  @essay_grading.topic = @essay_assignment.topic

  if @essay_assignment.rubric.present? && @essay_assignment.rubric['app_key'].present?
    @essay_grading.grading ||= {}
    @essay_grading.grading['app_key'] = @essay_assignment.rubric['app_key']['grading']
    @essay_grading.general_context ||= {}
    @essay_grading.general_context['app_key'] = @essay_assignment.rubric['app_key']['general_context']
  end

  if @essay_grading.save
    # 檢查是否有對應的作業分配，如果有則更新分配狀態
    # 只有非草稿狀態的提交才更新分配狀態
    update_assignment_status_if_needed unless @essay_grading.status == 'draft'

    render json: { success: true, essay_grading: @essay_grading }, status: :created
  else
    render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
  end
end

private

# 更新作業分配狀態（如果存在對應的分配記錄）
def update_assignment_status_if_needed
  # 查找對應的 AssignmentStudentAssignment
  assignment = AssignmentStudentAssignment.find_by(
    essay_assignment_id: @essay_assignment.id,
    general_user_id: current_general_user.id
  )

  # 如果存在分配記錄，說明是通過分配的作業進入，需要更新狀態
  if assignment
    assignment.update_columns(
      status: AssignmentStudentAssignment.statuses[:completed],
      completed_at: @essay_grading.created_at
    )
    Rails.logger.info "Updated assignment status for user #{current_general_user.id}, assignment #{@essay_assignment.id}"
  else
    # 如果不存在分配記錄，說明是直接通過 code 進入，不需要更新狀態
    Rails.logger.info "No assignment distribution found for user #{current_general_user.id}, assignment #{@essay_assignment.id} - skipping status update"
  end
end
```

### 4.2 修改 `update` 方法（可選）

如果學生可以更新已提交的作業（從 draft 變為其他狀態），也需要在 `update` 方法中添加類似的邏輯：

```ruby
def update
  set_essay_grading
  
  if @essay_grading.update(essay_grading_params)
    # 如果狀態從 draft 變為非 draft，需要更新分配狀態
    if @essay_grading.saved_change_to_status? && 
       @essay_grading.status != 'draft' && 
       @essay_grading.status_before_last_save == 'draft'
      update_assignment_status_if_needed
    end

    render json: { success: true, essay_grading: @essay_grading }, status: :ok
  else
    render json: { success: false, errors: @essay_grading.errors.full_messages }, status: :unprocessable_entity
  end
end
```

---

## 5. EssayGrading 模型回調（可選方案）

**注意**：如果選擇在控制器中處理，則不需要在模型中添加回調。但如果希望統一處理邏輯，也可以在模型中添加回調：

在 `app/models/essay_grading.rb` 中添加回調（僅在存在分配記錄時更新）：

```ruby
# 在 EssayGrading 模型中添加
after_create :update_assignment_status_if_assigned, if: -> { status != 'draft' }
after_update :update_assignment_status_if_assigned, if: -> { saved_change_to_status? && status != 'draft' && status_before_last_save == 'draft' }

private

def update_assignment_status_if_assigned
  # 查找對應的 AssignmentStudentAssignment
  assignment = AssignmentStudentAssignment.find_by(
    essay_assignment_id: essay_assignment_id,
    general_user_id: general_user_id
  )

  # 只有存在分配記錄時才更新狀態
  return unless assignment

  # 更新狀態為已完成
  assignment.update_columns(
    status: AssignmentStudentAssignment.statuses[:completed],
    completed_at: created_at
  )
end
```

**推薦方案**：在控制器中處理，因為：
1. 邏輯更清晰，可以明確區分是否通過分配進入
2. 可以記錄日誌，便於調試
3. 避免模型回調的複雜性

---

## 6. 實現步驟

1. **實現 `MyAssignmentsController#index` 方法**：
   - 獲取當前學生的所有作業分配
   - 支援按狀態過濾
   - 實現分頁
   - 返回統計信息

2. **擴展 `AssignmentStudentAssignment` 模型**：
   - 添加 `has_submission?` 方法
   - 添加 `essay_grading` 方法
   - 添加 `days_remaining` 方法
   - 添加 `overdue?` 方法

3. **修改 `EssayGradingsController#create` 方法**：
   - 在保存 `EssayGrading` 後，檢查是否存在對應的 `AssignmentStudentAssignment`
   - 如果存在，更新分配狀態為 `completed`
   - 如果不存在，不進行任何操作（說明是直接通過 code 進入）

4. **修改 `EssayGradingsController#update` 方法**（可選）：
   - 如果狀態從 `draft` 變為非 `draft`，也需要更新分配狀態

5. **測試功能**：
   - 測試學生查看作業列表
   - 測試按狀態過濾
   - 測試分頁功能
   - 測試通過分配的作業提交後狀態自動更新
   - 測試直接通過 code 提交不更新分配狀態

**注意**：後台任務實現請參考「任務 6」文檔，該任務應在完成其他任務後最後處理。

---

## 7. 驗收標準

- [ ] 學生可以查看自己的所有作業列表
- [ ] 支援按狀態過濾（assigned, completed, overdue）
- [ ] 支援分頁功能
- [ ] 返回統計信息（各狀態的數量）
- [ ] 通過分配的作業提交（非草稿）後，對應的 `AssignmentStudentAssignment` 狀態自動更新為 `completed`
- [ ] 通過分配的作業提交時，`completed_at` 字段自動設置
- [ ] 直接通過 code 提交的作業，不會更新分配狀態（因為沒有對應的分配記錄）
- [ ] 系統能正確區分是否通過分配進入
- [ ] `days_remaining` 方法正確計算剩餘天數
- [ ] `overdue?` 方法正確判斷是否逾期
- [ ] 所有 API 都有適當的權限驗證

---

## 8. 注意事項

1. **狀態更新時機**：
   - 學生提交作業時立即更新狀態（僅當存在分配記錄時）
   - 逾期狀態的更新可以通過後台任務定期處理（參考「任務 6」文檔）

2. **分配記錄檢查**：
   - 必須在保存 `EssayGrading` 後檢查是否存在 `AssignmentStudentAssignment`
   - 只有存在分配記錄時才更新狀態
   - 直接通過 code 進入的作業不應該影響分配狀態

3. **性能考慮**：
   - 使用 `update_columns` 直接更新數據庫，避免觸發回調
   - 分配記錄的查找使用 `find_by`，避免不必要的查詢

4. **數據一致性**：
   - 確保 `EssayGrading` 和 `AssignmentStudentAssignment` 的狀態保持一致（僅當存在分配記錄時）
   - 如果 `EssayGrading` 被刪除，需要考慮是否要更新 `AssignmentStudentAssignment` 狀態

5. **草稿處理**：
   - 草稿狀態的 `EssayGrading` 不應該觸發狀態更新
   - 只有非草稿的提交才會更新狀態

6. **時區處理**：
   - 確保截止日期的比較使用正確的時區

7. **日誌記錄**：
   - 記錄分配狀態更新的操作，便於調試和追蹤
   - 區分「通過分配進入」和「直接通過 code 進入」的情況
