# 任務 4：實現老師查看未完成作業學生的 API

## 任務目標

實現老師查看作業完成情況統計的 API，包括各學生的提交狀態、班級級別統計等功能。

## 任務範圍

1. 實現作業完成情況統計 API
2. 實現按班級、狀態過濾的功能
3. 實現學生列表分頁功能
4. 創建統計服務對象

---

## 1. API 接口

### 1.1 獲取作業完成情況統計

**端點**: `GET /api/v1/essay_assignments/:essay_assignment_id/statistics`

**描述**: 獲取指定作業的完成情況統計，包括各學生的提交狀態。

**認證**: 需要 JWT Token，且用戶必須是作業創建者或同校教師

**查詢參數**:
- `class_name` (可選): 按班級過濾
- `status` (可選): 按狀態過濾：`assigned`, `completed`, `overdue`
- `page` (可選): 頁碼，默認 1
- `per_page` (可選): 每頁數量，默認 25

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
        "student_email": "zhang@example.com",
        "class_name": "1A",
        "class_number": "01",
        "status": "completed",
        "submitted_at": "2024-01-15T10:00:00Z",
        "deadline": "2024-12-31T23:59:59Z",
        "is_overdue": false
      }
    ]
  },
  "meta": {
    "pagination": {
      "current_page": 1,
      "next_page": 2,
      "prev_page": null,
      "total_pages": 2,
      "total_count": 50
    }
  }
}
```

---

## 2. 服務對象實現

### 2.1 `AssignmentStatisticsService`

**文件**: `app/services/assignment_statistics_service.rb`

```ruby
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
                             .joins(:general_user)
                             .joins('INNER JOIN student_enrollments ON student_enrollments.general_user_id = general_users.id')
                             .joins('INNER JOIN school_academic_years ON school_academic_years.id = student_enrollments.school_academic_year_id')
                             .where(student_enrollments: { status: :active })
                             .where('school_academic_years.status = ?', SchoolAcademicYear.statuses[:active])

    if class_name.present?
      query = query.where(student_enrollments: { class_name: class_name })
    end

    query = query.where(status: status) if status.present?

    # 按班級、學號排序（學號從小到大）
    # 使用 CAST 將學號轉換為數字進行排序，如果轉換失敗則按字符串排序
    # 注意：Rails 6+ 要求使用 Arel.sql() 包裝原始 SQL 字符串
    query.order(Arel.sql('student_enrollments.class_name ASC, 
                 CASE 
                   WHEN general_users.class_no ~ \'^[0-9]+$\' 
                   THEN CAST(general_users.class_no AS INTEGER) 
                   ELSE 999999 
                 END ASC,
                 general_users.class_no ASC'))
  end

  private

  def calculate_by_class(base_query)
    # 獲取所有相關的班級
    class_names = StudentEnrollment
      .joins(:general_user)
      .where(general_user_id: base_query.select(:general_user_id))
      .where(status: :active)
      .distinct
      .pluck(:class_name)

    class_names.map do |class_name|
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

---

## 3. 控制器實現

### 3.1 `AssignmentStatisticsController` 完整實現

**文件**: `app/controllers/api/v1/assignment_statistics_controller.rb`

```ruby
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
          # 從關聯中獲取當前學年的 enrollment
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

---

## 4. 實現步驟

1. **創建服務對象**：
   - 創建 `AssignmentStatisticsService` 類
   - 實現 `calculate` 方法計算統計數據
   - 實現 `students_query` 方法獲取學生列表
   - 實現 `calculate_by_class` 方法計算班級級別統計

2. **實現控制器**：
   - 實現 `AssignmentStatisticsController#show` 方法
   - 調用服務對象獲取統計數據
   - 實現分頁功能
   - 格式化響應數據
   - 確保學生列表按班級、學號排序

3. **測試功能**：
   - 測試獲取完整統計數據
   - 測試按班級過濾
   - 測試按狀態過濾
   - 測試分頁功能
   - 測試權限驗證

---

## 5. 驗收標準

- [ ] 可以獲取作業的完整統計數據（總數、已完成、待完成、逾期、完成率）
- [ ] 可以獲取按班級分組的統計數據
- [ ] 可以獲取學生列表，包含每個學生的詳細信息
- [ ] 支援按班級過濾
- [ ] 支援按狀態過濾（assigned, completed, overdue）
- [ ] 支援分頁功能
- [ ] 學生列表按班級、學號排序（學號從小到大）
- [ ] 返回的學生信息包含：姓名、郵箱、班級、學號、狀態、提交時間、截止時間、是否逾期
- [ ] 只有同校的教師可以查看統計
- [ ] 所有錯誤情況都有適當的錯誤響應

---

## 注意事項

1. **性能優化**：
   - 使用 `includes` 預加載關聯數據，避免 N+1 查詢
   - 對於大量數據，考慮使用緩存

2. **查詢優化**：
   - 確保所有查詢字段都有適當的索引
   - 使用 `joins` 而不是 `includes` 進行過濾
   - 排序時使用數字轉換確保學號按數字大小排序，而非字符串排序（例如：1, 2, 10 而不是 1, 10, 2）

3. **數據準確性**：
   - 確保統計數據與實際數據一致
   - 完成率計算要考慮除零情況

4. **分頁處理**：
   - 使用 `Kaminari.paginate_array` 對數組進行分頁
   - 返回完整的分頁元數據

5. **權限控制**：
   - 確保只有同校的教師可以查看統計
   - 驗證作業創建者或同校教師身份
