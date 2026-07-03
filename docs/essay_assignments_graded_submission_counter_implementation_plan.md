# EssayAssignment `number_of_submission` 方案 A 可执行实施方案（混合读取）

> **状态**：已确认方案，待编码（确认后方可开始编写代码）  
> **确认日期**：2026-06-04  
> **关联文档**：[essay_assignments_number_of_submission_spec.md](./essay_assignments_number_of_submission_spec.md)  
> **方案代号**：**方案 A — 混合读取（Hybrid Index）**

---

## 1. 方案摘要（已确认）

| 项 | 决策 |
|----|------|
| 统计口径（新数据） | **非 draft**：`pending` + `graded` + `stopped` 计入，`draft` 不计 |
| 是否删除 `counter_cache` | **否**，保持 `EssayGrading` 现有 `counter_cache: :number_of_submission` |
| 历史数据回填 | **不做**（无全量 migration UPDATE） |
| 旧 Assignment（index） | 直接读表字段 `essay_assignments.number_of_submission`（counter_cache 值） |
| 新 Assignment（index） | SELECT 内嵌**标量子查询**实时统计非 draft 数量 |
| 改动范围 | ** primarily `EssayAssignmentsController#index`** + 可选索引 migration |
| 前端 | 字段名不变，仍为 `number_of_submission` |

---

## 2. 背景与动机

### 2.1 当前问题

| 层级 | 现状 | 问题 |
|------|------|------|
| `EssayAssignmentsController#index` | `LEFT JOIN essay_gradings` + `GROUP BY` + `COUNT(status != draft)` | 语义正确，但 **JOIN 膨胀 + 聚合慢** |
| `essay_assignments.number_of_submission` | Rails `counter_cache` 维护 | 任意 status 创建 grading 均 +1（**含 draft**），与「非 draft」语义不一致 |
| 数据量 | 历史 assignment / grading 很多 | **不适合**全量 migration 回填 |

### 2.2 为何采用混合读取

在「不回填、不改 model、保留 counter_cache」约束下：

- **旧数据**：counter_cache 已在列中，直接读取 **零额外成本**；虽可能略大于真实非 draft 数（draft 被计入），但产品接受作为历史兼容
- **新数据**：部署后创建的 assignment 用子查询，**index 展示准确的非 draft 数**
- **性能**：去掉全表 JOIN + GROUP BY；仅对新 assignment 行执行轻量子查询（有索引时成本低）

---

## 3. 统计口径定义

### 3.1 新数据（index 子查询）

```text
number_of_submission =
  COUNT(essay_gradings WHERE essay_assignment_id = ? AND status != draft)
```

| status | 值 | 新数据是否计入 |
|--------|-----|----------------|
| `pending` | 0 | ✅ |
| `graded` | 1 | ✅ |
| `stopped` | 2 | ✅ |
| `draft` | 3 | ❌ |

### 3.2 旧数据（index 读列）

```text
number_of_submission = essay_assignments.number_of_submission  （counter_cache 维护值）
```

**语义说明**：counter_cache 在 **创建** grading 时 +1（含 draft），**删除**时 -1，**不**随 status 在 draft ↔ 非 draft 间变化而调整。

因此旧数据展示值可能：

- **≥** 真实非 draft 数（若存在「只存 draft、未提交」的 grading）
- 在「先 draft 后提交」场景下，counter_cache 通常不会随 status 变更而修正，与子查询结果也可能有偏差

**产品已接受**：旧 Assignment 保留 counter_cache 展示，不做回填修正。

### 3.3 新旧数据边界

采用 **`created_at` 切分时间戳**（推荐，**零 schema 变更**）：

```ruby
# config/initializers/essay_assignment_submission_count.rb（实施时创建）
# 部署前在 staging 确定并写入生产环境变量
EssayAssignment::SUBMISSION_COUNT_LIVE_AT =
  ENV.fetch('SUBMISSION_COUNT_LIVE_AT') { '2026-06-04T00:00:00Z' }.then { |v| Time.zone.parse(v) }
```

| 条件 | index 行为 |
|------|------------|
| `essay_assignments.created_at < SUBMISSION_COUNT_LIVE_AT` | 读 `number_of_submission` 列 |
| `essay_assignments.created_at >= SUBMISSION_COUNT_LIVE_AT` | 子查询统计非 draft |

**切分点设置原则**：

- 设为 **生产部署完成时刻**（或略早 1 分钟），确保部署后新建 assignment 全部走子查询
- staging / production 使用不同 ENV 值
- 写入 runbook，避免误改导致大量 assignment 切换口径

**备选（本次不采用）**：新增布尔列 `uses_live_submission_count`，create 时默认 `true`——需 migration，暂不引入。

---

## 4. 架构设计

### 4.1 数据流

```text
                    GET /api/v1/essay_assignments.json (index)
                                      │
                                      ▼
                         essay_assignments 主表查询
                         （无 JOIN essay_gradings）
                         （无 GROUP BY）
                                      │
                    ┌─────────────────┴─────────────────┐
                    │                                   │
         created_at < LIVE_AT                 created_at >= LIVE_AT
                    │                                   │
                    ▼                                   ▼
      number_of_submission 列                 标量子查询 COUNT
      （counter_cache 值）                   （status != draft）
                    │                                   │
                    └─────────────────┬─────────────────┘
                                      ▼
                           JSON: number_of_submission
                           （前端无感知）
```

### 4.2 counter_cache 继续运行（不改）

```ruby
# essay_grading.rb — 保持不变
belongs_to :essay_assignment, counter_cache: :number_of_submission, optional: true
```

- 新 grading 创建仍更新列（供旧口径接口、详情页等使用）
- **index 对新 assignment 不读该列**，但列仍会被 counter_cache 写入
- 列值与新 assignment index 展示值 **可能不一致**——仅限 index 对新数据用子查询，属预期

### 4.3 核心 SQL（index SELECT 片段）

```sql
CASE
  WHEN essay_assignments.created_at < :live_at_timestamp THEN essay_assignments.number_of_submission
  ELSE (
    SELECT COUNT(*)
    FROM essay_gradings eg
    WHERE eg.essay_assignment_id = essay_assignments.id
      AND eg.status != 3
  )
END AS number_of_submission
```

`:live_at_timestamp` 由 Rails 绑定或 sanitize 传入（**禁止**字符串拼接未转义用户输入）。

### 4.4 与现有 `list_meta_sql_select` 的关系

index 已使用 `EssayAssignment.list_meta_sql_select` 剔除 `speaking_pronunciation_sentences`，本方案 **保持不变**，在同一 `select(...)` 中追加 `number_of_submission` 的 CASE 表达式即可。

---

## 5. 实施阶段

### Phase 0：准备（无代码）

- [x] 确认口径：新数据 **非 draft**（非仅 graded）
- [x] 确认方案 A：混合读取、不回填、保留 counter_cache
- [x] 确认旧数据接受 counter_cache 展示偏差
- [ ] 确定生产 `SUBMISSION_COUNT_LIVE_AT` 具体值（部署前填写）
- [ ] staging 验证通过后再上生产

### Phase 1：常量与 SQL  helper（model 层）

**文件**：`app/models/essay_assignment.rb`

新增（示意）：

```ruby
# 由 initializer 或 ENV 注入；model 内只读引用
def self.submission_count_live_at
  @submission_count_live_at ||= Time.zone.parse(
    ENV.fetch('SUBMISSION_COUNT_LIVE_AT', '2026-06-04T00:00:00Z')
  )
end

def self.index_submission_count_sql
  draft_status = EssayGrading.statuses[:draft]
  live_at = connection.quote(submission_count_live_at.utc.iso8601(6))

  <<~SQL.squish
    CASE
      WHEN essay_assignments.created_at < #{live_at} THEN essay_assignments.number_of_submission
      ELSE (
        SELECT COUNT(*)
        FROM essay_gradings eg
        WHERE eg.essay_assignment_id = essay_assignments.id
          AND eg.status != #{draft_status}
      )
    END AS number_of_submission
  SQL
end
```

**说明**：SQL 片段放在 model 便于复用与单测；**不**引入 SubmissionCounter 服务。

**新建（可选）**：`config/initializers/essay_assignment_submission_count.rb` 集中文档化 ENV。

### Phase 2：改造 `EssayAssignmentsController#index`

**文件**：`app/controllers/api/v1/essay_assignments_controller.rb`

**改前**：

```ruby
.left_outer_joins(:essay_gradings)
.select(..., COUNT(...) AS number_of_submission)
.group('essay_assignments.id')
```

**改后**：

```ruby
def index
  @essay_assignments = current_general_user.essay_assignments
  @essay_assignments = @essay_assignments.where(category: params[:category]) if params[:category].present?

  @essay_assignments = @essay_assignments
    .select(
      'essay_assignments.id',
      'essay_assignments.rubric',
      'essay_assignments.title',
      'essay_assignments.hints',
      'essay_assignments.category',
      'essay_assignments.answer_visible',
      'essay_assignments.topic',
      'essay_assignments.created_at',
      'essay_assignments.updated_at',
      'essay_assignments.code',
      'essay_assignments.assignment',
      EssayAssignment.list_meta_sql_select,
      EssayAssignment.index_submission_count_sql
    )
    .order('essay_assignments.created_at desc')
    .page(params[:page])
    .per(params[:count] || 10)

  render json: {
    success: true,
    essay_assignments: @essay_assignments.map(&:as_list_json),
    meta: pagination_meta(@essay_assignments)
  }, status: :ok
end
```

**要点**：

- 移除 `left_outer_joins(:essay_gradings)`、`group`、`draft_status` 局部变量
- 不再 `select` 裸 `number_of_submission` 列（由 CASE 表达式覆盖）
- Kaminari 分页 `total_count` 不再受 GROUP BY 影响

### Phase 3：索引 migration（强烈建议，非数据回填）

**新建**：`db/migrate/*_add_indexes_for_assignment_index_submission_count.rb`

```ruby
class AddIndexesForAssignmentIndexSubmissionCount < ActiveRecord::Migration[7.0]
  disable_ddl_transaction!

  def change
    add_index :essay_gradings,
              [:essay_assignment_id, :status],
              name: 'index_essay_gradings_on_assignment_id_and_status',
              algorithm: :concurrently

    add_index :essay_assignments,
              [:general_user_id, :category, :created_at],
              order: { created_at: :desc },
              name: 'index_essay_assignments_on_user_category_created_at',
              algorithm: :concurrently
  end
end
```

**说明**：

- 这是 **索引** migration，不是数据 UPDATE
- PostgreSQL 生产环境建议 `algorithm: :concurrently`（需 `disable_ddl_transaction!`）
- 子查询走 `(essay_assignment_id, status)` 索引；列表过滤走 `(general_user_id, category, created_at)`

### Phase 4：测试

**新建**：`test/models/essay_assignment_index_submission_count_test.rb`

| # | 场景 | 期望 |
|---|------|------|
| 1 | `index_submission_count_sql` 含 CASE 与子查询 | SQL 结构正确 |
| 2 | created_at 早于 LIVE_AT | SQL 分支读列 |
| 3 | created_at 晚于 LIVE_AT | SQL 分支为子查询 |

**新建 / 扩展**：`test/controllers/api/v1/essay_assignments_controller_index_test.rb`

| # | 场景 | 期望 |
|---|------|------|
| 1 | 旧 assignment，列值为 5 | index 返回 5（不跑子查询逻辑层面的集成验证） |
| 2 | 新 assignment，2 pending + 1 draft | index 返回 2 |
| 3 | 新 assignment，无 grading | 返回 0 |
| 4 | index 不触发 JOIN essay_gradings | 可 mock / assert_queries 或 EXPLAIN |

### Phase 5：文档与环境

- [ ] 部署 runbook 记录 `SUBMISSION_COUNT_LIVE_AT` 设置方式
- [ ] 更新 [essay_assignments_number_of_submission_spec.md](./essay_assignments_number_of_submission_spec.md) 注明 index 混合口径（实施完成后）
- [ ] 本文档状态改为「已实施」并记录 PR / 部署日

---

## 6. 文件改动清单

| 操作 | 路径 | 说明 |
|------|------|------|
| 修改 | `app/models/essay_assignment.rb` | 新增 `submission_count_live_at`、`index_submission_count_sql` |
| 修改 | `app/controllers/api/v1/essay_assignments_controller.rb` | `#index` 去掉 JOIN/GROUP BY |
| 新建（建议） | `config/initializers/essay_assignment_submission_count.rb` | ENV 说明 |
| 新建（建议） | `db/migrate/*_add_indexes_...rb` | 仅索引，无数据变更 |
| 新建 | `test/models/essay_assignment_index_submission_count_test.rb` | SQL helper 测试 |
| 新建/扩展 | `test/controllers/.../essay_assignments_controller_index_test.rb` | 集成测试 |

**明确不改**

| 文件 | 原因 |
|------|------|
| `app/models/essay_grading.rb` | 保留 counter_cache |
| `app/controllers/api/v1/communities_controller.rb` | 本次范围外，仍读列 |
| `#show` / `#read` / `#by_community` | 仍读 `number_of_submission` 列 |
| 前端 `essay-checker` | 字段名与结构不变 |
| 任何全量数据回填 migration | 用户明确不做 |

---

## 7. 其它接口行为（实施后的预期）

| 接口 | `number_of_submission` 来源 | 口径 |
|------|----------------------------|------|
| `GET /api/v1/essay_assignments.json` (**index**) | 混合：旧读列 / 新子查询 | 旧≈counter_cache；新=非 draft |
| `GET /api/v1/essay_assignments/:id` (show) | 表字段 | counter_cache（全创建计数，含 draft） |
| `GET .../read` | 表字段 | 同上 |
| `GET .../by_community` | 表字段 | 同上 |
| `CommunitiesController` 作业列表 | 表字段 | 同上 |

**已知不一致（接受）**：

- 同一 assignment 在 **index（新）** vs **show** 可能数字不同（index 非 draft，show 为 counter_cache）
- 仅影响 **部署后新建** 且 **存在 draft grading** 的 assignment
- 若未来需统一，可另开任务对 show/community 应用相同 CASE 逻辑

---

## 8. 性能分析

### 8.1 优化点

| 优化 | 说明 |
|------|------|
| 去掉 JOIN + GROUP BY | 主查询只扫 `essay_assignments`，分页 count 更准确 |
| 旧数据零子查询成本 | CASE 短路，直接读列 |
| 索引 | 新数据子查询走 `(essay_assignment_id, status)` |

### 8.2 列表页实际负载

index 按 `created_at DESC` 排序，**第一页多为新 assignment**（子查询），深分页多为旧 assignment（读列）。

典型每页 10 条：最多 10 次子查询（新数据行），每次 O(log n) 索引扫描，通常远轻于原「JOIN 全量 grading 再 GROUP BY」。

### 8.3 验收 EXPLAIN

```sql
EXPLAIN (ANALYZE, BUFFERS)
SELECT
  essay_assignments.id,
  CASE
    WHEN essay_assignments.created_at < '2026-06-04T00:00:00Z' THEN essay_assignments.number_of_submission
    ELSE (
      SELECT COUNT(*) FROM essay_gradings eg
      WHERE eg.essay_assignment_id = essay_assignments.id AND eg.status != 3
    )
  END AS number_of_submission
FROM essay_assignments
WHERE general_user_id = '...'
ORDER BY created_at DESC
LIMIT 10;
```

**期望**：

- 无 `HashAggregate` over large join
- 子查询出现 `Index Scan` on `index_essay_gradings_on_assignment_id_and_status`

---

## 9. 验收标准

### 9.1 新 assignment（created_at >= LIVE_AT）

```sql
-- 应对齐：index 返回值 = 非 draft 计数
SELECT COUNT(*) FROM essay_gradings
WHERE essay_assignment_id = :id AND status != 3;
```

### 9.2 旧 assignment（created_at < LIVE_AT）

```sql
-- 应对齐：index 返回值 = 表字段
SELECT number_of_submission FROM essay_assignments WHERE id = :id;
```

### 9.3 API

| 检查项 | 期望 |
|--------|------|
| index 响应时间 | 较现网 JOIN 方案下降（staging 对比） |
| 新 assignment + draft only | index 显示 0 |
| 新 assignment + 1 pending | index 显示 1 |
| 旧 assignment | index 显示列值（即使与子查询结果不同也属预期） |

### 9.4 测试命令

```bash
cd DocAI_Backend_Rails
SUBMISSION_COUNT_LIVE_AT='2026-01-01T00:00:00Z' bin/rails test \
  test/models/essay_assignment_index_submission_count_test.rb \
  test/controllers/api/v1/essay_assignments_controller_index_test.rb
```

---

## 10. 部署步骤

```text
1. 合并 PR（index + model helper + 索引 migration + 测试）
2. 设置生产 ENV：
   SUBMISSION_COUNT_LIVE_AT=<生产部署完成 UTC 时间>
3. bin/rails db:migrate   # 仅索引，无数据 UPDATE
4. 部署应用
5. 新建一条 assignment 验证 index 走子查询（非 draft 计数）
6. 打开旧 assignment 列表项验证仍显示历史数字
7. EXPLAIN ANALYZE 抽查（§8.3）
```

### 回滚策略

| 情况 | 动作 |
|------|------|
| index 逻辑有问题 | 回滚 controller + model helper 代码即可 |
| 索引 migration 已执行 | 可保留索引，无害；或单独 migration 删除索引 |
| ENV 切分点设错 | 修正 `SUBMISSION_COUNT_LIVE_AT` 并重启应用（不改数据） |

**无需**数据 migration 回滚。

---

## 11. 风险与缓解

| 风险 | 影响 | 缓解 |
|------|------|------|
| 新旧口径并存 | 用户困惑（同列表不同 assignment 精度不同） | 文档说明；旧数据随时间淡出首页 |
| index vs show 不一致（新 assignment） | 详情页数字与列表不同 | 接受；或后续 show 同步 CASE |
| LIVE_AT 配置错误 | 大量 assignment 走错分支 | deploy checklist + staging  rehearsal |
| 新 assignment 子查询无索引 | 慢 | Phase 3 索引 migration |
| counter_cache 列继续涨 | 列对新 index 无意义但占语义 | 不影响 index；长期可选方案 B 统一 |

---

## 12. 未纳入本次范围

- 修改 / 移除 `counter_cache`
- 全量或分批数据回填
- `communities` / `show` / `read` 接口口径统一
- Admin / School 后台统计口径
- 前端文案调整
- `index` 后端 `search` 参数

---

## 13. 已确认清单

- [x] **语义（新数据）**：`number_of_submission` = 非 draft（pending + graded + stopped）
- [x] **语义（旧数据）**：index 读 counter_cache 列，不做修正
- [x] **方案**：方案 A 混合读取
- [x] **不改 model**：保留 `counter_cache`
- [x] **不回填**：无全量 UPDATE migration
- [ ] **索引**：建议同期添加 §Phase 3 索引（实施时可确认）
- [ ] **LIVE_AT**：部署前确定具体 ENV 值

---

## 14. 确认后的执行 Checklist（给开发者）

```text
□ Phase 1  EssayAssignment.index_submission_count_sql + ENV
□ Phase 2  EssayAssignmentsController#index 改造
□ Phase 3  索引 migration（concurrently）
□ Phase 4  单元 / 集成测试
□ Phase 5  部署 runbook + 文档状态更新
□ 设置 SUBMISSION_COUNT_LIVE_AT 并部署
□ §9 验收
```

---

## 附录 A：备选方案（本次未采用）

<details>
<summary>方案 B — 自定义 counter + 去 counter_cache（点击展开）</summary>

- 去掉 `counter_cache`，在 `EssayGrading` 维护非 draft 计数
- index 直接读列，性能最佳，全站可统一口径
- 需改 model、处理 `update_columns` 路径
- 历史数据需回填或 Sidekiq 分批修正

详见早期草案；因数据量大且用户选择不回填，**暂不实施**。

</details>

<details>
<summary>方案 A 纯子查询 — 全部 assignment 均用子查询（点击展开）</summary>

- 不区分新旧，index 始终 `COUNT(status != draft)`
- 语义最一致，旧数据也准确
- 每行均子查询，旧数据无「读列」优化
- 本次用户明确要求旧读列、新读子查询，**不采用纯子查询**。

</details>

---

**文档维护**：编码实施完成后请将顶部状态改为「已实施」，并注明 PR 号、生产 `SUBMISSION_COUNT_LIVE_AT` 与部署日期。
