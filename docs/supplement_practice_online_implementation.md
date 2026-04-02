# 补充练习在线完成功能实现文档

## 一、需求概述

将现有的 PDF 下载式补充练习改为在线完成系统，实现以下功能：
1. 学生在线完成补充练习（填充题、选择题、判断题）
2. 即时计分，无需调用外部 API
3. 支持草稿保存和正式提交两种状态
4. 记录完成时间和得分
5. 学生和老师可查看练习记录
6. 支持生成 PDF 报告

## 二、数据库设计

### 2.1 新建表：`supplement_practice_records`

```ruby
# db/migrate/YYYYMMDDHHMMSS_create_supplement_practice_records.rb
class CreateSupplementPracticeRecords < ActiveRecord::Migration[7.0]
  def change
    create_table :supplement_practice_records, id: :uuid do |t|
      # 关联字段
      t.references :essay_grading, null: false, foreign_key: true, type: :uuid, index: true
      t.references :general_user, null: false, foreign_key: true, type: :uuid, index: true
      t.references :essay_assignment, null: false, foreign_key: true, type: :uuid, index: true
      
      # 状态：draft（草稿）、submitted（已提交）
      t.integer :status, default: 0, null: false
      
      # 分数信息
      t.decimal :score, precision: 10, scale: 2, default: 0.0
      t.decimal :full_score, precision: 10, scale: 2, default: 0.0
      t.integer :questions_count, default: 0
      
      # 时间记录
      t.integer :using_time, default: 0, comment: '完成用时（秒）'
      t.datetime :started_at, comment: '开始时间'
      t.datetime :submitted_at, comment: '提交时间'
      
      # 答案数据（JSONB）
      # 格式：{ questions: [{ id: 1, type: 'fill_in_the_blank', user_answer: '...', ... }, ...] }
      t.jsonb :answers, default: {}, null: false
      
      # 原始题目数据（JSONB，从 supplement_practice 解析后存储）
      # 格式：{ questions: [{ id: 1, type: 'fill_in_the_blank', question: '...', correct_answer: '...', ... }, ...] }
      t.jsonb :questions_data, default: {}, null: false
      
      # 元数据
      t.jsonb :meta, default: {}, null: false
      
      t.timestamps
    end
    
    # 索引
    add_index :supplement_practice_records, [:essay_grading_id, :general_user_id], 
              name: 'index_supplement_practice_on_grading_and_user'
    add_index :supplement_practice_records, :status
    add_index :supplement_practice_records, :submitted_at
    add_index :supplement_practice_records, [:general_user_id, :status]
    add_index :supplement_practice_records, [:essay_assignment_id, :status],
              name: 'index_supplement_practice_on_assignment_and_status'
    
    # 唯一约束：每个 essay_grading 和 general_user 组合只能有一条 submitted 记录
    # 但可以有多个 draft 记录（允许多次保存草稿）
    # 注意：PostgreSQL 的 partial unique index 语法
    add_index :supplement_practice_records, 
              [:essay_grading_id, :general_user_id], 
              unique: true, 
              where: "status = 1", # 只对 submitted 状态应用唯一约束
              name: 'index_supplement_practice_unique_submitted'
  end
end
```

### 2.2 数据字段说明

#### `answers` JSONB 结构（学生提交的答案）：
```json
{
  "sections": [
    {
      "topic": "Spelling and Typographical Errors",
      "type": "multiple_choice",
      "questions": [
        {
          "question": "She received a beautifull gift for her birthday. What is the correct spelling?",
          "user_answer": "beautiful"
        },
        {
          "question": "He always beleives in himself no matter what. What is the correct spelling?",
          "user_answer": "believes"
        }
      ]
    },
    {
      "topic": "Incorrect Use of True/False Question Format",
      "type": "true_or_false",
      "questions": [
        {
          "statement": "\"Is it true that cats can fly?\"",
          "user_answer": false
        },
        {
          "statement": "\"True or false: Water freezes at 0 degrees Celsius.\"",
          "user_answer": true
        }
      ]
    },
    {
      "topic": "Grammar and Word Choice Errors",
      "type": "fill_in_the_blanks",
      "questions": [
        {
          "question": "She ___ to the store every Saturday. (go/goes/going)",
          "id": "blank_1",
          "user_answer": "goes"
        },
        {
          "question": "\"There are many ___ in the park today.\" (child/children/childs)",
          "id": "blank_2",
          "user_answer": "children"
        }
      ]
    }
  ]
}
```

#### `questions_data` JSONB 结构（原始题目数据，从 supplement_practice 解析后存储）：
```json
{
  "quizTitle": "English Grammar Quiz",
  "sections": [
    {
      "topic": "Spelling and Typographical Errors",
      "type": "multiple_choice",
      "instructions": "Choose the correct spelling for the underlined word in each sentence.",
      "questions": [
        {
          "question": "She received a beautifull gift for her birthday. What is the correct spelling?",
          "options": [
            "beautifull",
            "beautiful",
            "beautifulll",
            "beauteful"
          ],
          "answer": "beautiful"
        },
        {
          "question": "He always beleives in himself no matter what. What is the correct spelling?",
          "options": [
            "beleives",
            "believes",
            "believs",
            "beleves"
          ],
          "answer": "believes"
        }
      ]
    },
    {
      "topic": "Incorrect Use of True/False Question Format",
      "type": "true_or_false",
      "instructions": "Read each statement and choose whether it is a properly formatted true/false question.",
      "questions": [
        {
          "statement": "\"Is it true that cats can fly?\"",
          "answer": false
        },
        {
          "statement": "\"True or false: Water freezes at 0 degrees Celsius.\"",
          "answer": true
        }
      ]
    },
    {
      "topic": "Grammar and Word Choice Errors",
      "type": "fill_in_the_blanks",
      "instructions": "Fill in the blank with the best word choice to complete each sentence correctly.",
      "questions": [
        {
          "question": "She ___ to the store every Saturday. (go/goes/going)",
          "id": "blank_1",
          "answer": "goes"
        },
        {
          "question": "\"There are many ___ in the park today.\" (child/children/childs)",
          "id": "blank_2",
          "answer": "children"
        }
      ]
    }
  ]
}
```

**注意：**
- `questions_data` 存储完整的原始题目数据（包括正确答案，用于计分和显示）
- `answers` 只存储学生的答案
- 题型可能随机出现，某些题型可能不存在（如可能只有选择题，没有判断题）

## 三、数据解析服务

### 3.1 创建解析服务：`SupplementPracticeParserService`

**文件位置：** `app/services/supplement_practice_parser_service.rb`

**功能：**
- 解析 `essay_grading.grading['supplement_practice']['text']` 中的 JSON 字符串
- 验证和规范化题目数据结构
- 为前端提供标准化的题目格式

**数据来源：**
- `essay_grading.grading['supplement_practice']['text']` 存储的是 JSON 字符串
- 需要解析为 Ruby Hash 对象

**数据结构说明：**
根据提供的示例数据，`supplement_practice['text']` 包含以下结构：
```json
{
  "quizTitle": "English Grammar Quiz",
  "sections": [
    {
      "topic": "主题名称",
      "type": "multiple_choice" | "true_or_false" | "fill_in_the_blanks",
      "instructions": "说明文字",
      "questions": [...]
    }
  ]
}
```

**题目类型说明：**

1. **multiple_choice（选择题）**
   - `question`: 题目文本
   - `options`: 选项数组（字符串数组）
   - `answer`: 正确答案（字符串，对应 options 中的某个值）

2. **true_or_false（判断题）**
   - `statement`: 陈述文本
   - `answer`: 正确答案（布尔值 true/false）

3. **fill_in_the_blanks（填充题）**
   - `question`: 题目文本（包含占位符）
   - `id`: 题目唯一标识（如 "blank_1"）
   - `answer`: 正确答案（字符串）

**实现要点：**
- 使用 `JSON.parse` 解析 JSON 字符串
- 验证数据结构完整性
- 处理可能的格式不一致（如某些字段缺失）
- 为每个题目生成全局唯一 ID（如果原数据没有提供）
- 扁平化处理：将 sections 中的题目提取为单一列表，便于前端渲染和计分

## 四、计分逻辑

### 4.1 创建计分服务：`SupplementPracticeScoringService`

**文件位置：** `app/services/supplement_practice_scoring_service.rb`

**计分规则：**

1. **填充题（fill_in_the_blanks）**
   - 不区分大小写比较
   - 去除首尾空格后比较
   - 答对得 1 分，答错得 0 分
   - 示例：`user_answer: "goes"` vs `correct_answer: "goes"` → 正确

2. **选择题（multiple_choice）**
   - 精确匹配答案字符串（区分大小写）
   - 用户答案必须完全匹配 `options` 数组中的某个选项值
   - 答对得 1 分，答错得 0 分
   - 示例：`user_answer: "beautiful"` vs `correct_answer: "beautiful"` → 正确

3. **判断题（true_or_false）**
   - 布尔值比较（true/false）
   - 如果用户提交的是字符串，需要转换为布尔值后比较
   - 答对得 1 分，答错得 0 分
   - 示例：`user_answer: true` vs `correct_answer: true` → 正确

**计分流程：**
1. 遍历 `questions_data` 中的所有 sections 和 questions
2. 根据题目类型匹配对应的 `user_answer`
3. 按照上述规则比较答案
4. 累计总分和题目数量
5. 返回：总分、满分、每题得分详情、正确率

**返回数据结构：**
```ruby
{
  score: 8,
  full_score: 10,
  questions_count: 10,
  correct_count: 8,
  incorrect_count: 2,
  details: [
    {
      section_topic: "Spelling and Typographical Errors",
      question_index: 0,
      type: "multiple_choice",
      is_correct: true,
      user_answer: "beautiful",
      correct_answer: "beautiful"
    },
    ...
  ]
}
```

## 五、API 设计

### 5.1 学生端 API

#### 5.1.1 获取补充练习题目
```
GET /api/v1/essay_gradings/:essay_grading_id/supplement_practice
```

**功能：**
- 从 `essay_grading.grading['supplement_practice']['text']` 解析 JSON 数据
- 返回结构化的题目数据（不包含正确答案，学生端）
- 如果有已保存的草稿或已提交记录，返回记录信息

**响应：**
```json
{
  "success": true,
  "data": {
    "essay_grading_id": "uuid",
    "quizTitle": "English Grammar Quiz",
    "sections": [
      {
        "topic": "Spelling and Typographical Errors",
        "type": "multiple_choice",
        "instructions": "Choose the correct spelling for the underlined word in each sentence.",
        "questions": [
          {
            "question": "She received a beautifull gift for her birthday. What is the correct spelling?",
            "options": [
              "beautifull",
              "beautiful",
              "beautifulll",
              "beauteful"
            ]
            // 注意：不返回 answer 字段（学生端）
          },
          ...
        ]
      },
      {
        "topic": "Incorrect Use of True/False Question Format",
        "type": "true_or_false",
        "instructions": "Read each statement and choose whether it is a properly formatted true/false question.",
        "questions": [
          {
            "statement": "\"Is it true that cats can fly?\""
            // 注意：不返回 answer 字段（学生端）
          },
          ...
        ]
      },
      {
        "topic": "Grammar and Word Choice Errors",
        "type": "fill_in_the_blanks",
        "instructions": "Fill in the blank with the best word choice to complete each sentence correctly.",
        "questions": [
          {
            "question": "She ___ to the store every Saturday. (go/goes/going)",
            "id": "blank_1"
            // 注意：不返回 answer 字段（学生端）
          },
          ...
        ]
      }
    ],
    "has_existing_record": true, // 是否有已保存的记录（草稿或已提交）
    "existing_record": { // 如果有，返回记录信息
      "id": "uuid",
      "status": "draft", // 或 "submitted"
      "answers": {
        "sections": [...]
      },
      "score": 0, // 如果是草稿，score 为 0
      "full_score": 10,
      "using_time": 120
    }
  }
}
```

#### 5.1.2 保存草稿
```
POST /api/v1/essay_gradings/:essay_grading_id/supplement_practice/draft
```

**功能：**
- 保存学生的答案为草稿状态
- 可以多次保存（覆盖之前的草稿）
- 不计算分数

**请求体：**
```json
{
  "answers": {
    "sections": [
      {
        "topic": "Spelling and Typographical Errors",
        "type": "multiple_choice",
        "questions": [
          {
            "question": "She received a beautifull gift for her birthday. What is the correct spelling?",
            "user_answer": "beautiful"
          },
          ...
        ]
      },
      {
        "topic": "Incorrect Use of True/False Question Format",
        "type": "true_or_false",
        "questions": [
          {
            "statement": "\"Is it true that cats can fly?\"",
            "user_answer": false
          },
          ...
        ]
      },
      {
        "topic": "Grammar and Word Choice Errors",
        "type": "fill_in_the_blanks",
        "questions": [
          {
            "question": "She ___ to the store every Saturday. (go/goes/going)",
            "id": "blank_1",
            "user_answer": "goes"
          },
          ...
        ]
      }
    ]
  },
  "using_time": 120 // 已用时间（秒）
}
```

**响应：**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "status": "draft",
    "saved_at": "2025-01-XX..."
  }
}
```

#### 5.1.3 提交练习
```
POST /api/v1/essay_gradings/:essay_grading_id/supplement_practice/submit
```

**功能：**
- 提交练习并即时计算分数
- 每个作业只能提交一次（如果已提交，返回错误）
- 提交后状态变为 `submitted`，不能再修改

**请求体：**
```json
{
  "answers": {
    "sections": [
      {
        "topic": "Spelling and Typographical Errors",
        "type": "multiple_choice",
        "questions": [
          {
            "question": "She received a beautifull gift for her birthday. What is the correct spelling?",
            "user_answer": "beautiful"
          },
          ...
        ]
      },
      {
        "topic": "Incorrect Use of True/False Question Format",
        "type": "true_or_false",
        "questions": [
          {
            "statement": "\"Is it true that cats can fly?\"",
            "user_answer": false
          },
          ...
        ]
      },
      {
        "topic": "Grammar and Word Choice Errors",
        "type": "fill_in_the_blanks",
        "questions": [
          {
            "question": "She ___ to the store every Saturday. (go/goes/going)",
            "id": "blank_1",
            "user_answer": "goes"
          },
          ...
        ]
      }
    ]
  },
  "using_time": 300 // 总用时（秒）
}
```

**响应：**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "score": 8,
    "full_score": 10,
    "questions_count": 10,
    "correct_count": 8,
    "incorrect_count": 2,
    "submitted_at": "2025-01-XX..."
  }
}
```

**错误响应（如果已提交）：**
```json
{
  "success": false,
  "error": "该作业的练习已经提交，不能重复提交"
}
```

#### 5.1.4 查看自己的练习记录
```
GET /api/v1/supplement_practice_records/:id
```

**功能：**
- 查看已提交的练习记录详情
- 显示每题的对错情况和正确答案

**响应：**
```json
{
  "success": true,
  "data": {
    "id": "uuid",
    "essay_grading_id": "uuid",
    "essay_grading": {
      "id": "uuid",
      "topic": "作业标题",
      "assignment": "作业内容"
    },
    "status": "submitted",
    "score": 8,
    "full_score": 10,
    "questions_count": 10,
    "correct_count": 8,
    "incorrect_count": 2,
    "using_time": 300,
    "started_at": "...",
    "submitted_at": "...",
    "quizTitle": "English Grammar Quiz",
    "sections": [
      {
        "topic": "Spelling and Typographical Errors",
        "type": "multiple_choice",
        "instructions": "Choose the correct spelling...",
        "questions": [
          {
            "question": "She received a beautifull gift for her birthday. What is the correct spelling?",
            "options": ["beautifull", "beautiful", "beautifulll", "beauteful"],
            "user_answer": "beautiful",
            "correct_answer": "beautiful",
            "is_correct": true
          },
          ...
        ]
      },
      {
        "topic": "Incorrect Use of True/False Question Format",
        "type": "true_or_false",
        "instructions": "Read each statement...",
        "questions": [
          {
            "statement": "\"Is it true that cats can fly?\"",
            "user_answer": false,
            "correct_answer": false,
            "is_correct": true
          },
          ...
        ]
      },
      {
        "topic": "Grammar and Word Choice Errors",
        "type": "fill_in_the_blanks",
        "instructions": "Fill in the blank...",
        "questions": [
          {
            "question": "She ___ to the store every Saturday. (go/goes/going)",
            "id": "blank_1",
            "user_answer": "goes",
            "correct_answer": "goes",
            "is_correct": true
          },
          ...
        ]
      }
    ]
  }
}
```

#### 5.1.5 生成 PDF 报告
```
GET /api/v1/supplement_practice_records/:id/download_report
```

**功能：**
- 生成补充练习的 PDF 报告
- 参考 `generate_comprehension_pdf` 方法的样式和布局
- 显示题目、学生答案、正确答案、得分情况

**PDF 内容结构：**
1. 报告标题：Supplementary Practice Report
2. 作业信息：Assignment、Topic、Account
3. 分数概览：Overall Score
4. 题目详情（按 section 分组）：
   - Section 标题和说明
   - 每题的题目内容
   - 学生答案（标注对错）
   - 正确答案（仅已提交时显示）

**样式要求：**
- 与阅读理解 PDF 报告保持一致的样式
- 使用相同的字体和布局
- 支持学校 Logo（如果有）

### 5.2 教师端 API

#### 5.2.1 通过作业ID查看该作业的所有练习记录（推荐方式）
```
GET /api/v1/essay_assignments/:essay_assignment_id/supplement_practice_records
```

**功能：**
- 通过 `essay_assignment_id` 直接查询该作业的所有补充练习记录
- 返回所有提交记录和统计信息
- 这是推荐的方式，因为可以直接通过作业ID查询，无需先获取 essay_grading_id

**查询参数：**
- `status`: 筛选状态（draft/submitted，默认 submitted）
- `page`: 页码
- `per_page`: 每页数量

**响应：**
```json
{
  "success": true,
  "data": {
    "records": [
      {
        "id": "uuid",
        "general_user": {
          "id": "uuid",
          "nickname": "学生姓名",
          "email": "email@example.com"
        },
        "essay_grading": {
          "id": "uuid",
          "topic": "作业标题"
        },
        "status": "submitted",
        "score": 8,
        "full_score": 10,
        "using_time": 300,
        "submitted_at": "..."
      },
      ...
    ],
    "statistics": {
      "total_submitted": 25,
      "total_draft": 3,
      "average_score": 7.5,
      "average_using_time": 280,
      "completion_rate": 0.89
    },
    "meta": {
      "current_page": 1,
      "total_pages": 3,
      "total_count": 25
    }
  }
}
```

#### 5.2.2 查看某个作业的所有练习记录（方式 B：通过 essay_grading_id）
```
GET /api/v1/essay_gradings/:essay_grading_id/supplement_practice_records
```

**查询参数：**
- `status`: 筛选状态（draft/submitted，默认 submitted）
- `page`: 页码
- `per_page`: 每页数量

**响应：**
```json
{
  "success": true,
  "data": {
    "records": [
      {
        "id": "uuid",
        "general_user": {
          "id": "uuid",
          "nickname": "学生姓名",
          "email": "email@example.com"
        },
        "status": "submitted",
        "score": 8,
        "full_score": 10,
        "using_time": 300,
        "submitted_at": "..."
      },
      ...
    ],
    "statistics": {
      "total_submitted": 25,
      "total_draft": 3,
      "average_score": 7.5,
      "average_using_time": 280,
      "completion_rate": 0.89 // 提交率
    },
    "meta": {
      "current_page": 1,
      "total_pages": 3,
      "total_count": 25
    }
  }
}
```

#### 5.2.3 查看某个作业的练习记录（方式 C：作业关联视图）
```
GET /api/v1/essay_gradings/:essay_grading_id/supplement_practice_records/by_assignment
```

**功能：**
- 列出所有提交了该作业的学生
- 显示每个学生是否有对应的练习记录
- 统计提交情况

**响应：**
```json
{
  "success": true,
  "data": {
    "students": [
      {
        "general_user": {
          "id": "uuid",
          "nickname": "学生A",
          "email": "a@example.com"
        },
        "essay_grading": {
          "id": "uuid",
          "submitted_at": "...",
          "status": "graded"
        },
        "supplement_practice_record": {
          "id": "uuid",
          "status": "submitted",
          "score": 8,
          "full_score": 10,
          "submitted_at": "..."
        } // 如果没有记录则为 null
      },
      {
        "general_user": {...},
        "essay_grading": {...},
        "supplement_practice_record": null // 未提交练习
      },
      ...
    ],
    "statistics": {
      "total_students": 30,
      "submitted_count": 25,
      "not_submitted_count": 5,
      "average_score": 7.5,
      "submission_rate": 0.83
    }
  }
}
```

## 六、查看方式分析（方式 A vs 方式 B）

### 6.1 方式 A：列表视图（所有已完成的练习记录）

**优点：**
- 简单直观，直接显示所有提交的练习记录
- 查询性能好，只需查询 `supplement_practice_records` 表
- 适合快速查看整体完成情况和平均分
- 实现简单，代码量少

**缺点：**
- 无法直接看到哪些学生没有提交练习
- 无法关联到具体的作业提交情况
- 如果学生多次提交（理论上不应该，但如果有 bug），可能显示多条记录

**适用场景：**
- 快速查看整体统计
- 不需要关联作业提交情况
- 只需要关注已完成的练习

### 6.2 方式 B：作业关联视图（每份作业对应一个练习记录）

**优点：**
- 可以清楚看到每个学生的作业提交和练习完成情况
- 方便识别未提交练习的学生
- 数据关联性强，便于分析作业完成度与练习完成度的关系
- 符合业务逻辑：一份作业对应一份练习

**缺点：**
- 查询复杂度高，需要 JOIN `essay_gradings` 和 `supplement_practice_records`
- 如果作业数量大，可能影响性能
- 需要处理没有提交作业但有练习记录的情况（边缘情况）

**适用场景：**
- 需要详细分析每个学生的完成情况
- 需要识别未提交的学生
- 需要关联作业和练习的完成度

### 6.3 推荐方案

**建议同时提供两种方式，但默认使用方式 B（作业关联视图）**

**理由：**
1. **业务需求更匹配**：方式 B 更符合"每份作业对应一份练习"的业务逻辑
2. **教师体验更好**：可以清楚看到谁提交了、谁没提交，便于跟进
3. **性能可控**：通过适当的索引和查询优化，性能问题可以解决
4. **灵活性**：提供两种方式，教师可以根据需要选择

**性能优化建议：**
- 在 `essay_grading_id` 和 `general_user_id` 上建立联合索引
- 使用 `includes` 预加载关联数据，避免 N+1 查询
- 对于大量数据，使用分页
- 考虑添加缓存（如 Redis）存储统计信息

## 七、模型设计

### 7.1 SupplementPracticeRecord 模型

**文件位置：** `app/models/supplement_practice_record.rb`

```ruby
class SupplementPracticeRecord < ApplicationRecord
  belongs_to :essay_grading
  belongs_to :general_user
  belongs_to :essay_assignment
  
  enum status: { draft: 0, submitted: 1 }
  
  # 验证
  # 注意：唯一性约束在数据库层面通过 partial unique index 实现
  # 这里添加应用层验证作为双重保障
  validate :ensure_single_submission_per_grading
  
  def ensure_single_submission_per_grading
    return unless submitted? # 只对 submitted 状态进行验证
    
    existing = self.class.where(
      essay_grading_id: essay_grading_id,
      general_user_id: general_user_id,
      status: :submitted
    ).where.not(id: id)
    
    if existing.exists?
      errors.add(:base, '每个作业只能提交一次练习')
    end
  end
  
  # 作用域
  scope :submitted, -> { where(status: :submitted) }
  scope :by_essay_grading, ->(essay_grading_id) { where(essay_grading_id: essay_grading_id) }
  scope :by_essay_assignment, ->(essay_assignment_id) { where(essay_assignment_id: essay_assignment_id) }
  
  # 方法
  def calculate_score
    # 调用 SupplementPracticeScoringService 计算分数
  end
  
  def completion_percentage
    return 0 if full_score.zero?
    (score / full_score * 100).round(2)
  end
end
```

### 7.2 EssayGrading 模型关联

在 `app/models/essay_grading.rb` 中添加：

```ruby
has_many :supplement_practice_records, dependent: :destroy
has_one :submitted_supplement_practice_record, 
        -> { where(status: :submitted) },
        class_name: 'SupplementPracticeRecord'
```

### 7.3 EssayAssignment 模型关联

在 `app/models/essay_assignment.rb` 中添加：

```ruby
has_many :supplement_practice_records, dependent: :destroy
```

## 八、控制器设计

### 8.1 学生端控制器

**文件位置：** `app/controllers/api/v1/supplement_practice_records_controller.rb`

**主要方法：**
- `show` - 获取题目
- `create_draft` - 保存草稿
- `submit` - 提交练习
- `show_record` - 查看记录
- `download_report` - 下载 PDF

### 8.2 教师端控制器

**文件位置：** `app/controllers/api/v1/supplement_practice_records_controller.rb`（共用，通过权限区分）

或单独创建：`app/controllers/api/v1/teachers/supplement_practice_records_controller.rb`

**主要方法：**
- `index` - 列表视图（方式 A）
- `by_assignment` - 作业关联视图（方式 B）

## 九、前端实现要点

### 9.1 页面路由

- 学生端：`/essay-gradings/:id/supplement-practice`
- 学生查看记录：`/supplement-practice-records/:id`
- 教师查看记录：`/essay-gradings/:id/supplement-practice-records`

### 9.2 组件结构

```
components/
  supplement-practice/
    SupplementPracticeForm.tsx      # 主表单组件
    QuestionRenderer.tsx            # 题目渲染器
    FillInTheBlankQuestion.tsx      # 填充题组件
    MultipleChoiceQuestion.tsx      # 选择题组件
    TrueFalseQuestion.tsx           # 判断题组件
    Timer.tsx                       # 计时器组件
    SaveDraftButton.tsx             # 保存草稿按钮
    SubmitButton.tsx                 # 提交按钮
```

### 9.3 状态管理

- 使用 React Hooks（useState, useReducer）管理表单状态
- 实时保存草稿（可考虑防抖，避免频繁请求）
- 提交前验证必填项

## 十、实现步骤

### Phase 1: 数据库和模型（1-2 天）
1. 创建 migration
2. 创建 SupplementPracticeRecord 模型
3. 添加关联关系
4. 编写测试

### Phase 2: 数据解析服务（1-2 天）
1. ✅ 已确认数据格式为 JSON 结构（参考 supplement_practice.json）
2. 实现 SupplementPracticeParserService
   - 解析 JSON 字符串
   - 验证数据结构完整性
   - 处理缺失字段的情况
3. 编写解析测试用例
4. 处理各种边缘情况（如某些题型不存在、字段缺失等）

### Phase 3: 计分服务（1-2 天）
1. 实现 SupplementPracticeScoringService
2. 编写计分测试用例
3. 验证计分准确性

### Phase 4: API 实现（3-4 天）
1. 实现学生端 API
2. 实现教师端 API（两种查看方式）
3. 添加权限验证
4. 编写 API 测试

### Phase 5: PDF 生成（1-2 天）
1. 参考 `generate_comprehension_pdf` 方法实现
2. 使用相同的样式和布局（字体、间距、颜色等）
3. 按 section 分组显示题目
4. 显示每题的对错情况（✅/❌）
5. 测试 PDF 生成

### Phase 6: 前端实现（5-7 天）
1. 创建页面和组件
2. 实现题目渲染
3. 实现表单提交
4. 实现记录查看页面
5. 实现教师端查看页面

### Phase 7: 测试和优化（2-3 天）
1. 端到端测试
2. 性能优化
3. 用户体验优化
4. Bug 修复

**总计：约 14-22 个工作日**（数据格式已确认，减少了解析复杂度）

## 十一、注意事项

1. ✅ **数据格式**：已确认 supplement_practice text 为 JSON 格式，结构见 `supplement_practice.json`
2. **唯一性约束**：
   - 每个学生每个作业只能提交一次练习（status = submitted）
   - 草稿可以多次保存（status = draft），每次保存覆盖之前的草稿
   - 使用 PostgreSQL partial unique index 实现数据库层面的唯一性约束
3. **权限控制**：
   - 学生只能查看和操作自己的记录
   - 教师可以查看所有学生的记录
   - 在控制器中使用 `before_action` 进行权限验证
4. **性能考虑**：
   - 对于大量学生的作业，使用适当的索引和分页
   - 使用 `includes` 预加载关联数据，避免 N+1 查询
   - 考虑对统计信息进行缓存
5. **错误处理**：
   - JSON 解析失败：返回友好的错误信息
   - 题目数据缺失：使用默认值或跳过该题目
   - 计分错误：记录日志，返回错误信息
6. **数据兼容性**：
   - 处理题型可能不存在的情况（如可能只有选择题，没有判断题）
   - 处理题目字段可能缺失的情况
7. **题目格式**：
   - 题目为纯文字，不包含图片
   - 支持 Markdown 格式的题目文本（如需要）

## 十二、已确认事项

1. ✅ **数据格式**：supplement_practice text 为 JSON 格式，结构见 `supplement_practice.json`
2. ✅ **题目类型**：支持 multiple_choice、true_or_false、fill_in_the_blanks 三种题型
3. ✅ **题型随机性**：题型可能有可无，随机生成
4. ✅ **提交规则**：
   - 学生可以提交多个作业，每个作业对应一份练习
   - 每个作业只能做一份练习，但可以多次保存草稿
   - 每个练习只能提交一次（status = submitted）
5. ✅ **题目格式**：纯文字，不包含图片或音频
6. ✅ **PDF 样式**：参考阅读理解生成的 PDF 格式，保持一致
7. ✅ **草稿保存**：建议使用防抖（debounce），避免频繁请求（如 2-3 秒内只保存一次）

## 十三、补充说明

### 13.1 题目 ID 生成规则

由于原始数据中：
- `multiple_choice` 和 `true_or_false` 类型的题目没有 `id` 字段
- `fill_in_the_blanks` 类型的题目有 `id` 字段（如 "blank_1"）

**处理方案：**
- 在解析时，为所有题目生成全局唯一 ID
- 格式：`"question_#{section_index}_#{question_index}"`（如 "question_0_0"）
- 对于 fill_in_the_blanks，如果已有 id，则使用原有 id；否则生成新 id
- 在存储 `answers` 时，使用相同的 ID 进行匹配

### 13.2 答案匹配逻辑

在计分时，需要根据题目类型和 ID 匹配用户答案：

```ruby
# 匹配规则：
# 1. 通过 section 的 topic 和 type 定位到对应的 section
# 2. 在 section 的 questions 中查找匹配的题目
#    - multiple_choice: 通过 question 文本匹配
#    - true_or_false: 通过 statement 文本匹配
#    - fill_in_the_blanks: 通过 id 匹配（优先）或 question 文本匹配
```

### 13.3 前端题目渲染顺序

前端应按照 `sections` 的顺序渲染：
1. 显示 `quizTitle`（如果有）
2. 遍历 `sections`，按顺序显示每个 section
3. 每个 section 显示：
   - `topic`（标题）
   - `instructions`（说明）
   - `questions`（题目列表）

---

**文档版本：** v1.0  
**创建日期：** 2025-01-XX  
**最后更新：** 2025-01-XX
