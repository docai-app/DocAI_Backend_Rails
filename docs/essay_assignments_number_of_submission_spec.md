## EssayAssignment 提交次数统计优化方案

### 1. 背景与现状

- **当前实现**
  - 模型 `EssayGrading` 中的关联如下：
    - `belongs_to :essay_assignment, counter_cache: :number_of_submission, optional: true`
  - 数据库中在 `essay_assignments` 表上有字段：
    - `number_of_submission :integer, default: 0, null: false`
  - Rails 默认的 `counter_cache` 行为：
    - 每当创建一条新的 `EssayGrading` 记录时（无论 `status` 是什么），都会将对应 `EssayAssignment` 的 `number_of_submission` 自增 1。
    - 删除记录时会自减 1。
  - `EssayAssignmentsController#index` 以及 `CommunitiesController` 的部分接口，都会直接把 `essay_assignments.number_of_submission` 作为「提交次数」返回给前端。

- **问题**
  - 新增了 `draft` 状态，用于学生「先保存草稿，不立即批改」：
    - `enum status: { pending: 0, graded: 1, stopped: 2, draft: 3 }`
  - 由于 `counter_cache` 不区分 `status`，保存草稿（`draft`）时也会增加 `number_of_submission`。
  - 导致：
    - 列表接口中展示的 `number_of_submission` 包含了草稿与真正完成/批改的作业，统计偏大，与「真实提交数」不符。

### 2. 需求目标

- **核心目标**
  - 在获取 `EssayAssignments#index`（以及相关接口）时：
    - `number_of_submission` 仅统计 **状态为 `graded` 的作业数量**。
- **具体要求**
  - 真实提交数目只计入已经完成批改的记录（`status = graded`）。
  - 需要在保证现有 API 基本结构不大幅度变化的前提下，修复统计逻辑。
  - 尽量保持前后端字段名不变（继续使用 `number_of_submission`）以减少前端改动。

### 3. 方案对比

#### 3.1 方案一：查询层按 `graded` 状态统计

- **思路**
  - 保持模型层 `counter_cache` 不变（仍然统计所有状态）。
  - 在 `EssayAssignmentsController#index` 等接口中，不直接使用表字段 `number_of_submission`，而是：
    - 通过 `LEFT JOIN` + `WHERE essay_gradings.status = graded` + `GROUP BY` 统计一个新的计数字段（例如 `graded_submissions_count`）。
    - 在返回 JSON 时，将该统计结果映射到返回的 `number_of_submission` 字段，或者增加一个新字段如 `graded_number_of_submission`。

- **实现要点（示意）**
  - 在 `index` 查询中：
    - 使用 `left_joins(:essay_gradings)` 并按 `essay_gradings.status = :graded` 过滤计数。
    - 使用 `select('essay_assignments.*, COUNT(essay_gradings.id) AS graded_submissions_count')` 并 `group('essay_assignments.id')`。
  - 在构造 JSON 时：
    - `number_of_submission = graded_submissions_count`（覆盖原字段语义），或
    - 同时返回 `number_of_submission`（原始计数）和 `graded_number_of_submission`（新计数）。

- **优点**
  - 不修改现有模型关联和数据库结构，改动集中在控制器层。
  - 便于灰度：可以先增加一个新字段供前端接入测试。

- **缺点**
  - `essay_assignments.number_of_submission` 字段的含义仍然是「所有状态计数」，与业务期望不一致。
  - 其它引用该字段的地方（例如 `CommunitiesController`、管理后台等）如果没有统一调整，会继续读到「错误的」计数。
  - 统计逻辑分散在多个控制器中，长期维护成本较高。

#### 3.2 方案二：基于状态的自定义计数器（推荐）

- **思路**
  - 放弃使用默认的 `counter_cache: :number_of_submission`。
  - 改为在 `EssayGrading` 中通过回调，**仅在 `status` 为 `graded` 时维护计数**：
    - 创建时如果是 `graded`：`number_of_submission += 1`
    - 状态从非 `graded` 变为 `graded`：`number_of_submission += 1`
    - 状态从 `graded` 变为其他状态：`number_of_submission -= 1`
    - 删除时如果当前是 `graded`：`number_of_submission -= 1`
  - 通过一次性数据修正任务，把历史数据中的 `number_of_submission` 重新计算为「graded 数量」。

- **实现要点（示意）**
  - 模型 `EssayGrading`：
    - 移除：`counter_cache: :number_of_submission`
    - 增加回调：
      - `after_create :increment_counter_if_graded`
      - `after_update :update_counter_if_status_changed`
      - `after_destroy :decrement_counter_if_graded`
    - 在回调中使用 `EssayAssignment.increment_counter` / `decrement_counter` 保证并发安全。
  - 数据迁移（Migration）：
    - 遍历所有 `EssayAssignment`，将 `number_of_submission` 重置为 `essay_gradings.where(status: :graded).count`。

- **优点**
  - 从数据层统一定义：`number_of_submission` 始终等于**已批改（graded）作业数**。
  - 所有读取该字段的地方（包括现有和未来的 API）都自动获得正确语义，避免重复实现统计逻辑。
  - 逻辑清晰，长远来看维护成本更低。

- **缺点**
  - 需要修改模型层逻辑并增加一条数据修正 Migration。
  - 存在一次性数据重算过程，需要在低峰期执行，并做好备份。

#### 3.3 结论

- **推荐采用：方案二「基于状态的自定义计数器」**
  - 原因：
    - 从根本上纠正 `number_of_submission` 的业务语义。
    - 对前端无感知或几乎无改动，避免在多个控制器/接口中重复写复杂统计查询。
    - 对后续统计、报表功能更友好。

### 4. 详细实施步骤（方案二）

#### 4.1 模型层调整：`EssayGrading`

1. **移除默认 counter_cache**

   - 现有代码中：
     - `belongs_to :essay_assignment, counter_cache: :number_of_submission, optional: true`
   - 调整为（示意）：
     - `belongs_to :essay_assignment, optional: true`

2. **新增基于 `status` 的计数回调（示意代码）**

   class EssayGrading < ApplicationRecord
     enum status: { pending: 0, graded: 1, stopped: 2, draft: 3 }

     belongs_to :essay_assignment, optional: true

     after_create :increment_counter_if_graded
     after_update :update_counter_if_status_changed
     after_destroy :decrement_counter_if_graded

     private

     def increment_counter_if_graded
       return unless essay_assignment_id.present?
       return unless graded?

       EssayAssignment.increment_counter(:number_of_submission, essay_assignment_id)
     end

     def decrement_counter_if_graded
       return unless essay_assignment_id.present?
       return unless graded?

       EssayAssignment.decrement_counter(:number_of_submission, essay_assignment_id)
     end

     def update_counter_if_status_changed
       return unless essay_assignment_id.present?
       return unless saved_change_to_status?

       before_status, after_status = saved_change_to_status.map(&:to_s)

       if before_status != 'graded' && after_status == 'graded'
         EssayAssignment.increment_counter(:number_of_submission, essay_assignment_id)
       elsif before_status == 'graded' && after_status != 'graded'
         EssayAssignment.decrement_counter(:number_of_submission, essay_assignment_id)
       end
     end
   end
   