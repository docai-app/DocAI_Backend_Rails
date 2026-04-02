# 任務 1：創建相關模型和控制器

## 任務目標

創建作業自動分派系統所需的數據模型、數據庫遷移文件和基礎控制器結構。

## 任務範圍

1. 創建3個新的數據表及其遷移文件
2. 創建3個新的模型類
3. 擴展現有模型（EssayAssignment 和 GeneralUser）
4. 創建4個基礎控制器結構

---

## 1. 數據庫遷移

### 1.1 創建 `assignment_distributions` 表

**文件**: `db/migrate/YYYYMMDDHHMMSS_create_assignment_distributions.rb`

```ruby
class CreateAssignmentDistributions < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_distributions, id: :uuid do |t|
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.references :school_academic_year, null: false, foreign_key: true, type: :uuid
      t.references :school, null: false, foreign_key: true, type: :uuid
      
      # 分配類型：class_name（班級）、individual（個別學生）
      t.string :distribution_type, null: false
      
      # 分配目標：班級名稱或學生ID
      t.string :target_class_name
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

### 1.2 創建 `assignment_student_assignments` 表

**文件**: `db/migrate/YYYYMMDDHHMMSS_create_assignment_student_assignments.rb`

```ruby
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

### 1.3 創建 `assignment_reminders` 表

**文件**: `db/migrate/YYYYMMDDHHMMSS_create_assignment_reminders.rb`

```ruby
class CreateAssignmentReminders < ActiveRecord::Migration[7.0]
  def change
    create_table :assignment_reminders, id: :uuid do |t|
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid
      t.references :general_user, null: false, foreign_key: true, type: :uuid
      t.references :reminder_sender, foreign_key: { to_table: :general_users }, type: :uuid
      
      # 提醒類型（僅支持 email）
      t.integer :reminder_type, default: 0 # email
      
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

---

## 2. 模型實現

### 2.1 `AssignmentDistribution` 模型

**文件**: `app/models/assignment_distribution.rb`

```ruby
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

    errors.add(:deadline, '截止日期必須在創建時間之後') if deadline <= created_at
  end
end
```

### 2.2 `AssignmentStudentAssignment` 模型

**文件**: `app/models/assignment_student_assignment.rb`

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

### 2.3 `AssignmentReminder` 模型

**文件**: `app/models/assignment_reminder.rb`

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

## 3. 擴展現有模型

### 3.1 `EssayAssignment` 模型擴展

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

### 3.2 `GeneralUser` 模型擴展

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

## 4. 控制器基礎結構

### 4.1 `AssignmentDistributionsController` 基礎結構

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

      # 方法將在任務2中實現
      # def distribution_options
      # end

      # def create
      # end

      # def index
      # end

      # def show
      # end

      # def update
      # end

      # def destroy
      # end

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
    end
  end
end
```

### 4.2 `MyAssignmentsController` 基礎結構

**文件**: `app/controllers/api/v1/my_assignments_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module V1
    class MyAssignmentsController < ApiController
      before_action :authenticate_general_user!
      before_action :ensure_student

      # 方法將在任務3中實現
      # def index
      # end

      private

      def ensure_student
        unless current_general_user.aienglish_role == 'student'
          render json: { success: false, error: 'Only students can view their assignments' }, 
                 status: :forbidden
        end
      end
    end
  end
end
```

### 4.3 `AssignmentStatisticsController` 基礎結構

**文件**: `app/controllers/api/v1/assignment_statistics_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module V1
    class AssignmentStatisticsController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment
      before_action :ensure_teacher_and_same_school

      # 方法將在任務4中實現
      # def show
      # end

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

### 4.4 `AssignmentRemindersController` 基礎結構

**文件**: `app/controllers/api/v1/assignment_reminders_controller.rb`

```ruby
# frozen_string_literal: true

module Api
  module V1
    class AssignmentRemindersController < ApiController
      before_action :authenticate_general_user!
      before_action :set_essay_assignment
      before_action :ensure_teacher_and_same_school

      # 方法將在任務5中實現
      # def create
      # end

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
    end
  end
end
```

---

## 5. 路由配置

在 `config/routes.rb` 中添加基礎路由結構：

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

      member do
        get 'statistics', to: 'assignment_statistics#show'
        post 'send_reminders', to: 'assignment_reminders#create'
      end
    end

    get 'essay_assignments/my_assignments', to: 'my_assignments#index'
  end
end
```

---

## 6. 實現步驟

1. **生成遷移文件**：
   ```bash
   rails generate migration CreateAssignmentDistributions
   rails generate migration CreateAssignmentStudentAssignments
   rails generate migration CreateAssignmentReminders
   ```

2. **編寫遷移文件**：將上述遷移代碼複製到對應的遷移文件中

3. **執行遷移**：
   ```bash
   rake db:migrate
   ```

4. **創建模型文件**：創建上述3個模型文件

5. **擴展現有模型**：在 `EssayAssignment` 和 `GeneralUser` 中添加關聯和方法

6. **創建控制器文件**：創建上述4個控制器基礎結構

7. **配置路由**：在 `config/routes.rb` 中添加路由

8. **測試基礎結構**：
   - 驗證遷移是否成功
   - 驗證模型關聯是否正確
   - 驗證控制器基礎結構是否可訪問

---

## 7. 驗收標準

- [ ] 3個數據表成功創建，包含所有必要的字段和索引
- [ ] 3個模型類創建成功，包含基本的驗證和關聯
- [ ] `EssayAssignment` 和 `GeneralUser` 模型擴展完成
- [ ] 4個控制器基礎結構創建成功
- [ ] 路由配置完成
- [ ] 所有文件可以正常加載，無語法錯誤

---

## 注意事項

1. **索引優化**：確保所有查詢字段都有適當的索引
2. **驗證邏輯**：模型驗證邏輯要完整，確保數據完整性
3. **關聯完整性**：確保所有關聯關係正確設置，包括 `dependent` 選項
4. **作業提交方式**：
   - 學生可以通過分配的作業進入（從「我的作業」列表）
   - 學生也可以直接通過 code 進入作業
   - 兩種方式都應該被支持，但只有通過分配進入的作業才會更新分配狀態
   - 詳細實現請參考「任務 3」文檔中的 `EssayGradingsController` 修改說明
5. **通知方式**：系統僅支持通過 email 方式發送提醒通知給學生
6. **分配類型**：系統支持按班級（class_name）或個別學生（individual）進行分配，不支持按年級分配