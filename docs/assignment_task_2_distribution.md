# 任務 2：實現老師分配作業給學生

## 任務目標

實現老師分配作業給學生的功能，支援按班級或個別學生進行分配，並支援根據多個學生ID批量增加或取消分配。

## 任務範圍

1. 實現獲取可分配選項的 API（班級、學生列表）
2. 實現創建作業分配的 API（支援單個和批量）
3. 實現查詢、更新、取消分配的 API
4. 實現根據多個學生ID批量增加分配的 API
5. 實現根據多個學生ID批量取消分配的 API
6. 實現自動創建學生分配記錄的回調邏輯

---

## 1. API 接口

### 1.1 獲取可分配的班級和學生列表

**端點**: `GET /api/v1/essay_assignments/distribution_options`

**描述**: 獲取當前老師所在學校的當前學年下，可分配的班級和學生列表。

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

### 1.2 創建作業分配

**端點**: `POST /api/v1/essay_assignments/:essay_assignment_id/distributions`

**描述**: 為指定作業創建分配記錄，支援按班級或個別學生分配。

**認證**: 需要 JWT Token，且用戶必須是作業創建者或同校教師

**單個分配請求體**:
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

**批量分配請求體**:
```json
{
  "distributions": [
    {
      "distribution_type": "class_name",
      "target_class_name": "1A",
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

### 1.3 獲取作業分配列表

**端點**: `GET /api/v1/essay_assignments/:essay_assignment_id/distributions`

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

### 1.4 獲取單個分配詳情

**端點**: `GET /api/v1/essay_assignments/:essay_assignment_id/distributions/:id`

**成功響應** (200 OK):
```json
{
  "success": true,
  "distribution": {
    "id": "uuid",
    "distribution_type": "class_name",
    "target_class_name": "1A",
    "deadline": "2024-12-31T23:59:59Z",
    "assigned_students_count": 25,
    "status": "active",
    "assigned_students": [
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

### 1.5 更新分配

**端點**: `PATCH /api/v1/essay_assignments/:essay_assignment_id/distributions/:id`

**請求體**:
```json
{
  "distribution": {
    "deadline": "2025-01-15T23:59:59Z"
  }
}
```

### 1.6 取消分配

**端點**: `DELETE /api/v1/essay_assignments/:essay_assignment_id/distributions/:id`

**成功響應** (200 OK):
```json
{
  "success": true,
  "message": "Distribution cancelled successfully"
}
```

### 1.7 批量增加學生分配

**端點**: `POST /api/v1/essay_assignments/:essay_assignment_id/distributions/add_students`

**描述**: 根據多個學生ID批量增加作業分配。

**認證**: 需要 JWT Token，且用戶必須是作業創建者或同校教師

**請求體**:
```json
{
  "student_ids": ["uuid1", "uuid2", "uuid3"],
  "deadline": "2024-12-31T23:59:59Z"
}
```

**成功響應** (200 OK):
```json
{
  "success": true,
  "added_count": 3,
  "skipped_count": 0,
  "message": "Successfully added 3 students to assignment"
}
```

**說明**:
- `student_ids`: 學生ID數組，必須是當前學校當前學年的學生
- `deadline`: 截止日期，會應用到所有新增的學生分配
- 如果學生已經被分配過該作業，則會跳過（不重複分配）
- 返回成功添加的數量和跳過的數量

### 1.8 批量取消學生分配

**端點**: `POST /api/v1/essay_assignments/:essay_assignment_id/distributions/remove_students`

**描述**: 根據多個學生ID批量取消作業分配。

**認證**: 需要 JWT Token，且用戶必須是作業創建者或同校教師

**請求體**:
```json
{
  "student_ids": ["uuid1", "uuid2", "uuid3"]
}
```

**成功響應** (200 OK):
```json
{
  "success": true,
  "removed_count": 3,
  "not_found_count": 0,
  "message": "Successfully removed 3 students from assignment"
}
```

**說明**:
- `student_ids`: 學生ID數組
- 如果學生沒有被分配過該作業，則會跳過
- 返回成功取消的數量和未找到的數量

---

## 2. 控制器實現

### 2.1 `AssignmentDistributionsController` 完整實現

**文件**: `app/controllers/api/v1/assignment_distributions_controller.rb`

```ruby
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

      # POST /api/v1/essay_assignments/:essay_assignment_id/distributions/add_students
      def add_students
        school = current_general_user.get_school
        academic_year = school&.current_academic_year

        return render_not_found('School or academic year not found') unless school && academic_year

        student_ids = params[:student_ids] || []
        deadline = params[:deadline]

        return render json: { success: false, error: 'student_ids and deadline are required' }, 
                      status: :bad_request if student_ids.empty? || deadline.blank?

        # 驗證學生是否屬於當前學校當前學年
        valid_students = GeneralUser
          .joins(:student_enrollments)
          .where(id: student_ids)
          .where(student_enrollments: { 
            school_academic_year_id: academic_year.id,
            status: :active 
          })
          .distinct

        if valid_students.count != student_ids.count
          return render json: { 
            success: false, 
            error: 'Some students are not in the current school academic year' 
          }, status: :unprocessable_entity
        end

        # 查找已存在的分配記錄
        existing_assignments = @essay_assignment.assignment_student_assignments
                                                 .where(general_user_id: student_ids)
                                                 .pluck(:general_user_id)

        new_student_ids = student_ids - existing_assignments

        return render json: {
          success: true,
          added_count: 0,
          skipped_count: student_ids.count,
          message: 'All students are already assigned'
        }, status: :ok if new_student_ids.empty?

        # 為每個學生創建分配記錄和 AssignmentStudentAssignment
        # 注意：這裡為每個學生創建一個 individual 類型的 distribution
        added_count = 0
        failed_student_ids = []

        new_student_ids.each do |student_id|
          begin
            # 為每個學生創建一個 individual 類型的 distribution
            distribution = @essay_assignment.assignment_distributions.create!(
              school: school,
              school_academic_year: academic_year,
              distribution_type: 'individual',
              target_student_id: student_id,
              deadline: deadline,
              status: :active
            )

            # create_student_assignments 回調會自動創建 AssignmentStudentAssignment
            added_count += 1
          rescue StandardError => e
            Rails.logger.error "Failed to add student #{student_id}: #{e.message}"
            failed_student_ids << student_id
          end
        end

        render json: {
          success: true,
          added_count: added_count,
          skipped_count: existing_assignments.count,
          failed_count: failed_student_ids.count,
          failed_student_ids: failed_student_ids,
          message: "Successfully added #{added_count} students to assignment"
        }, status: added_count > 0 ? :ok : :unprocessable_entity
      end

      # POST /api/v1/essay_assignments/:essay_assignment_id/distributions/remove_students
      def remove_students
        student_ids = params[:student_ids] || []

        return render json: { success: false, error: 'student_ids is required' }, 
                      status: :bad_request if student_ids.empty?

        # 查找要取消的分配記錄
        assignments_to_remove = @essay_assignment.assignment_student_assignments
                                                  .where(general_user_id: student_ids)

        removed_count = assignments_to_remove.count
        not_found_count = student_ids.count - removed_count

        # 獲取相關的 distribution IDs（用於後續清理）
        distribution_ids = assignments_to_remove.pluck(:assignment_distribution_id).uniq

        # 刪除 AssignmentStudentAssignment 記錄
        assignments_to_remove.destroy_all

        # 清理沒有關聯學生的 individual 類型的 distribution
        # 注意：只清理 individual 類型，class_name 類型的 distribution 保留
        @essay_assignment.assignment_distributions
                        .where(id: distribution_ids, distribution_type: 'individual')
                        .where.not(id: AssignmentStudentAssignment.select(:assignment_distribution_id))
                        .destroy_all

        render json: {
          success: true,
          removed_count: removed_count,
          not_found_count: not_found_count,
          message: "Successfully removed #{removed_count} students from assignment"
        }, status: :ok
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

---

## 3. 模型回調實現

### 3.1 `AssignmentDistribution` 模型回調

在 `app/models/assignment_distribution.rb` 中添加回調：

```ruby
after_create :create_student_assignments
after_update :update_student_assignments, if: :saved_change_to_deadline?

private

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

  # 使用 bulk insert 提高性能（需要 activerecord-import gem）
  # 如果沒有該 gem，使用批量插入
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
```

---

## 3.5 路由配置

在 `config/routes.rb` 中添加以下路由：

```ruby
namespace :api do
  namespace :v1 do
    resources :essay_assignments do
      collection do
        get 'distribution_options', to: 'assignment_distributions#distribution_options'
      end

      resources :distributions, controller: 'assignment_distributions', except: [:new, :edit] do
        collection do
          post 'add_students', to: 'assignment_distributions#add_students'
          post 'remove_students', to: 'assignment_distributions#remove_students'
        end
      end
    end
  end
end
```

---

## 4. 實現步驟

1. **實現 `distribution_options` 方法**：獲取可分配的班級和學生列表

2. **實現 `create` 方法**：支援單個和批量創建分配

3. **實現 `index` 方法**：獲取作業的所有分配記錄

4. **實現 `show` 方法**：獲取單個分配的詳情

5. **實現 `update` 方法**：更新分配信息（主要是截止日期）

6. **實現 `destroy` 方法**：取消分配

7. **實現 `add_students` 方法**：根據多個學生ID批量增加分配

8. **實現 `remove_students` 方法**：根據多個學生ID批量取消分配

9. **實現模型回調**：在 `AssignmentDistribution` 中添加 `create_student_assignments` 和 `update_student_assignments` 回調

10. **測試功能**：
    - 測試獲取分配選項
    - 測試創建分配（單個和批量）
    - 測試查詢分配
    - 測試更新分配
    - 測試取消分配
    - 測試批量增加學生分配
    - 測試批量取消學生分配
    - 測試自動創建學生分配記錄

---

## 5. 驗收標準

- [ ] 可以獲取當前學校當前學年的班級和學生列表
- [ ] 可以按班級創建分配
- [ ] 可以按個別學生創建分配
- [ ] 支援批量創建分配
- [ ] 創建分配時自動為所有目標學生創建 `AssignmentStudentAssignment` 記錄
- [ ] 可以查詢作業的所有分配記錄
- [ ] 可以查看單個分配的詳情（包括分配的學生列表）
- [ ] 可以更新分配的截止日期（會同步更新所有相關學生的截止日期）
- [ ] 可以取消分配
- [ ] 可以根據多個學生ID批量增加分配
- [ ] 可以根據多個學生ID批量取消分配
- [ ] 批量增加時，已分配的學生會被跳過（不重複分配）
- [ ] 批量取消時，未分配的學生會被跳過
- [ ] 所有 API 都有適當的權限驗證
- [ ] 所有錯誤情況都有適當的錯誤響應

---

## 注意事項

1. **性能優化**：批量創建學生分配記錄時，使用 `activerecord-import` gem 或批量插入以提高性能

2. **重複分配**：確保同一個作業不會重複分配給同一個學生（通過唯一索引和驗證）

3. **權限驗證**：確保只有同校的教師可以管理分配

4. **數據一致性**：更新分配的截止日期時，要同步更新所有相關學生的截止日期

5. **錯誤處理**：批量創建時，即使部分失敗也要返回成功創建的記錄和失敗的錯誤信息

6. **作業提交方式**：
   - 學生可以通過分配的作業進入（從「我的作業」列表）
   - 學生也可以直接通過 code 進入作業
   - 兩種方式都應該被支持，但只有通過分配進入的作業才會更新分配狀態
   - 詳細實現請參考「任務 3」文檔

7. **批量操作**：
   - 批量增加學生分配時，會驗證學生是否屬於當前學校當前學年
   - 已分配的學生會被自動跳過，不會重複分配
   - 批量取消時，會刪除對應的 `AssignmentStudentAssignment` 記錄
   - 批量操作應返回成功處理的數量和跳過的數量

8. **分配類型**：系統支持按班級（class_name）或個別學生（individual）進行分配，不支持按年級分配
