# AIEnglish 学生端作业 API 文档（登录 / Join Code / Speaking Pronunciation）

适用对象：前端开发（Web/移动端 H5）  
目标：覆盖登录、鉴权、个人资料、Assignment Code 校验、speaking_pronunciation 进入作业、草稿/提交、草稿列表等完整链路。

---

## 1. 接口总览（按业务流程）

1) 登录拿 token  
2) 拉取当前用户资料（含 AIEnglish 权限）  
3) 输入 Assignment Code 做验证并路由  
4) 进入 speaking_pronunciation 页面拉 assignment 信息  
5) 首次创建作文（可 `draft` 或 `pending`）  
6) 编辑草稿（先取 grading 详情，再更新）  
7) 拉取仅属于 speaking_pronunciation + draft 的作业记录

---

## 2. 鉴权与 Token 规则（非常重要）

### 2.1 登录接口返回 token 的位置
- 登录请求：`POST /general_users/sign_in.json`
- 成功后 token 在响应头：`authorization`
- 前端当前实现：`localStorage.setItem('token', token)`，后续所有业务接口都从这里读取。

### 2.2 后续请求如何带 token
- 请求头使用：

```http
Authorization: <登录响应头 authorization 的原值>
```

> 注意：前端目前是“原样透传”，不在代码里手工拼 `Bearer `。  
> 如果后端返回本身是 `Bearer xxx`，就 그대로传；如果后端改为其他格式，前端也会原样传。

### 2.3 哪些接口需要鉴权
- `Api::V1::EssayAssignmentsController`：`show_only` 也需要 `authenticate_general_user!`
- `Api::V1::EssayGradingsController`：除下载 PDF 外，均需要 `authenticate_general_user!`
- `Api::V1::GeneralUsersController`：`show_current_user` / `show_aienglish_profile` 需要鉴权

---

## 3. 登录 API（获取 token）

### 3.1 登录
- **URL**: `POST /general_users/sign_in.json`
- **Content-Type**: `application/json`
- **请求体**:

```json
{
  "general_user": {
    "email": "student@example.com",
    "password": "your_password"
  }
}
```

- **成功响应（body）**:

```json
{
  "success": true,
  "message": "Logged in successfully."
}
```

- **成功响应头（关键）**:
  - `authorization: <token>`

- **失败响应**:
  - HTTP `401`
  - `{"success": false, "error": "Invalid email or password."}`

### 3.2 登出（补充）
- **URL**: `DELETE /general_users/sign_out`
- 成功：`{"success": true, "message": "Logged out."}`

---

## 4. 获取个人资料 API

前端 AIEnglish 当前主要用这个：

### 4.1 获取 AIEnglish profile（推荐）
- **URL**: `GET /api/v1/general_users/me/aienglish`
- **Headers**: `Authorization`
- **用途**:
  - 获取当前用户角色（teacher/student）
  - 获取功能权限列表（前端用来判定是否可访问某类作业）
  - 获取 school、teaching_assignments、enrollments

- **关键返回字段（前端已使用）**:
  - `user.id`
  - `user.email`
  - `user.nickname`
  - `user.meta.aienglish_role`
  - `user.meta.aienglish_features_list`（前端映射为 `aienglish_feature_list`）
  - `user.teaching_assignments[]` / `user.enrollments[]`

### 4.2 通用 me（可选）
- **URL**: `GET /api/v1/general_users/me`
- 返回基础 user 信息（不如 `me/aienglish` 丰富）

---

## 5. 根据 Assignment Code 输入验证 API

### 5.1 Code 校验 + 获取 assignment 基础信息
- **URL**: `GET /api/v1/essay_assignments/:code/show_only.json`
- **Headers**: `Authorization`
- **说明**:
  - `:code` 就是用户输入的 Assignment Code
  - 后端会按 `code` 查 `EssayAssignment`
  - 同时执行权限检查：当前用户 `aienglish_features_list` 必须包含该 assignment 的 `category`

- **成功响应**:

```json
{
  "success": true,
  "essay_assignment": {
    "id": 123,
    "code": "abc-mnop-xyz",
    "category": "speaking_pronunciation",
    "title": "...",
    "topic": "...",
    "assignment": "...",
    "meta": {},
    "graph_image_url": "https://...",
    "sample_essay": "..."
  }
}
```

- **失败场景（注意很多返回是 200 + success=false）**:
  - code 不存在：`{success:false,error:"EssayAssignment not found"}`
  - 无权限：`{success:false,error:"Access denied"}`

---

## 6. 进入 speaking_pronunciation 作业：获取 Assignment 与相关信息

## 6.1 新作业入口（通过 code）
- 前端实际调用：`GET /api/v1/essay_assignments/:code/show_only.json`
- 关键字段：
  - `essay_assignment.category` 必须是 `speaking_pronunciation`
  - `essay_assignment.meta.speaking_pronunciation_sentences`（题目句子模板）
  - `essay_assignment.meta.speaking_pronunciation_pass_score`（通过阈值）

### 6.2 草稿编辑入口（通过 grading id）
先查 grading，再查 assignment：

1) `GET /api/v1/essay_gradings/:id.json`  
2) `GET /api/v1/essay_assignments/:assignment_id/read.json`

其中 `essay_gradings/:id` 会返回：
- `essay_grading.grading.speaking_pronunciation_sentences`（已保存作答）
- `essay_grading.status`（draft/pending/...）
- `essay_grading.essay_assignment`（含 category / meta / rubric 等）

---

## 7. 提交 speaking_pronunciation 作文 API（草稿 + 正常提交）

业务上有两种写法：
- 首次创建：`POST /api/v1/essay_assignments/:code/essay_gradings.json`
- 已有草稿更新：`PUT /api/v1/essay_gradings/:id.json`

> speaking_pronunciation 页面当前实现就是这两条。

### 7.1 创建（首次）
- **URL**: `POST /api/v1/essay_assignments/:code/essay_gradings.json`
- **Headers**: `Authorization`
- **Body 示例（草稿）**:

```json
{
  "essay_grading": {
    "status": "draft",
    "grading": {
      "speaking_pronunciation_sentences": [
        {
          "sentence": "I like apples.",
          "speaking_times": 1,
          "score": 92,
          "result": {
            "pronunciation_accuracy": 92,
            "real_transcript": "I like apples."
          }
        }
      ]
    }
  }
}
```

- **Body 示例（正常提交）**:
  - 把 `status` 改成 `pending`

```json
{
  "essay_grading": {
    "status": "pending",
    "grading": {
      "speaking_pronunciation_sentences": []
    }
  }
}
```

- **成功响应**: HTTP `201`

```json
{
  "success": true,
  "essay_grading": {
    "id": 999,
    "status": "draft"
  }
}
```

### 7.2 更新（草稿编辑后保存/提交）
- **URL**: `PUT /api/v1/essay_gradings/:id.json`
- **Headers**: `Authorization`
- **Body**: 与创建同结构
- **成功响应**: HTTP `200`

```json
{
  "success": true,
  "data": 999,
  "essay_grading": {
    "id": 999,
    "status": "pending"
  }
}
```

### 7.3 状态语义（前端务必统一）
- `draft`：草稿
- `pending`：已提交，待批改/待后续流程
- 其他状态（如 `graded`/`stopped`）由后续流程产生

### 7.4 speaking_pronunciation 相关字段（后端 permit）
`essay_grading.grading.speaking_pronunciation_sentences[]` 可传：
- `sentence`
- `speaking_times`
- `ipa_transcript`
- `score`
- `transcript_translation`
- `real_transcript`（数组）
- `result` 下：
  - `audiobase64`
  - `real_transcript`
  - `ipa_transcript`
  - `pronunciation_accuracy`
  - `real_transcripts`
  - `matched_transcripts`
  - `real_transcripts_ipa`
  - `matched_transcripts_ipa`
  - `pair_accuracy_category`
  - `start_time`
  - `end_time`
  - `is_letter_correct_all_words`

---

## 7.5 UniSound 结果封装（`handleResult`）说明

### A. 流程位置

1. 上游返回原始 payload：`payload`  
2. 取引擎结果：`engineResult = payload.EngineResult ?? payload.result ?? payload`  
3. 调用：`responseData = handleResult(engineResult)`  
4. 前端把 `responseData` 放进每个句子的 `result` 字段提交到 backend

### B. `handleResult` 输入要求

- 输入必须包含 `lines` 数组且至少 1 项，否则返回 `null`。  
- 实际只处理第一行：`firstLine = lines[0]`。  
- 关键源字段（来自 UniSound）：
  - `firstLine.sample`
  - `firstLine.usertext`
  - `firstLine.score`
  - `firstLine.words[]`（词级信息）
  - `words[].subwords[]`（子词/字母级信息，可选）

### C. `handleResult` 输出字段映射（重点）

输出对象（即最终 `result`）主要字段如下：

- `origin_data`
  - 原样保留 UniSound 结果，便于排错与追溯。

- `real_transcript`
  - 来源：`sample.trim()`，并在末尾补句号 `.`（非空时）。

- `pronunciation_accuracy`
  - 来源：`firstLine.score`
  - 格式：`toFixed(2)`，即字符串形式，如 `"87.50"`。

- `real_transcripts`
  - 来源：`sample.trim()`（不补句号）。

- `matched_transcripts`
  - 来源：`usertext.trim()`，非空时补 `.`。

- `ipa_transcript` / `real_transcripts_ipa` / `matched_transcripts_ipa`
  - 来源：`words` 中每个词的 `phonetic`，若无则拼接 `subwords[].subtext`。
  - `real_transcripts_ipa`：纯 IPA 串（空格分隔）。
  - `ipa_transcript`：`real_transcripts_ipa + "."`（非空时）。
  - `matched_transcripts_ipa`：当前实现与 `real_transcripts_ipa` 同源并补 `.`。

- `pair_accuracy_category`
  - 逐词正确性标签，按空格拼接。
  - 规则：`word.score >= 8` 记 `"1"`，否则 `"0"`。

- `start_time` / `end_time`
  - 逐词时间戳（来源 `word.begin` / `word.end`），空格拼接。

- `is_letter_correct_all_words`
  - 字母级正确性串。
  - 若有 `subwords`：按 `subword.score >= 8` 决定 `1/0`，并按 grapheme 长度重复。
  - 若无 `subwords`：按词级 `word.score >= 8`，按 `word.text.length` 重复。
  - 词与词之间插入空格。

- `warnings`（可选）
  - 来自 `audiocheck`，如 `too short / emptyAudio / noise / volume / cut` 命中时生成提示数组。

### D. 可直接提交 backend 的 `result` 示例

> 下面是 `handleResult` 产出的典型结构示例，可直接放进  
> `essay_grading.grading.speaking_pronunciation_sentences[i].result`

```json
{
  "origin_data": {
    "lines": [
      {
        "sample": "I like apples",
        "usertext": "I like apple",
        "score": 87.5,
        "words": [
          {
            "type": 2,
            "text": "I",
            "phonetic": "aɪ",
            "score": 9,
            "begin": 120,
            "end": 240
          },
          {
            "type": 2,
            "text": "like",
            "phonetic": "laɪk",
            "score": 8,
            "begin": 250,
            "end": 520
          },
          {
            "type": 2,
            "text": "apples",
            "phonetic": "ˈæpəlz",
            "score": 6,
            "begin": 530,
            "end": 920
          }
        ]
      }
    ]
  },
  "real_transcript": "I like apples.",
  "ipa_transcript": "aɪ laɪk ˈæpəlz.",
  "pronunciation_accuracy": "87.50",
  "real_transcripts": "I like apples",
  "matched_transcripts": "I like apple.",
  "real_transcripts_ipa": "aɪ laɪk ˈæpəlz",
  "matched_transcripts_ipa": "aɪ laɪk ˈæpəlz.",
  "pair_accuracy_category": "1 1 0",
  "start_time": "120 250 530",
  "end_time": "240 520 920",
  "is_letter_correct_all_words": "1 1111 000000"
}
```

### E. 和提交 API 的组合示例

```json
{
  "essay_grading": {
    "status": "draft",
    "grading": {
      "speaking_pronunciation_sentences": [
        {
          "sentence": "I like apples.",
          "speaking_times": 1,
          "score": 87.5,
          "result": {
            "pronunciation_accuracy": "87.50",
            "real_transcript": "I like apples.",
            "matched_transcripts": "I like apple.",
            "pair_accuracy_category": "1 1 0",
            "start_time": "120 250 530",
            "end_time": "240 520 920",
            "is_letter_correct_all_words": "1 1111 000000"
          }
        }
      ]
    }
  }
}
```

### F. 实施建议

1. `result.origin_data` 建议保留，便于回放和定位评分异常。  
2. `pronunciation_accuracy` 是字符串（两位小数），前端展示时可转数字。  
3. 若 `handleResult` 返回 `null`，应视为评分失败，不要提交空壳 result。  
4. `warnings` 建议在 UI 提示用户（如录音太短、噪音过大）。

### G. 原处理方式（可跨语言复刻）

> 以下是 `route.ts` 里原始处理逻辑的“等价流程版”。  
> 如果前端不是 TypeScript（例如 Kotlin / Swift / Dart / Java / Python），可按此步骤实现同样结果。

#### G.1 预处理与容错入口

1. 读取 UniSound 返回对象 `result`。  
2. 取 `lines = result.lines`。  
3. 若 `result` 为空、`lines` 不存在、或 `lines.length == 0`，直接返回 `null`。  
4. 仅处理第一行：`firstLine = lines[0]`。  

#### G.2 基础字段提取

1. `sample = firstLine.sample || ""`  
2. `usertext = firstLine.usertext || ""`  
3. `pronunciation = Number(firstLine.score || 0)`  
4. `words = firstLine.words || []`  
5. 过滤仅保留发音词项：`words = words.filter(type == 2)`  

#### G.3 逐词循环处理（核心）

初始化容器：
- `ipaWords = []`
- `startTimes = []`
- `endTimes = []`
- `pairAccuracyCategory = []`
- `isLetterCorrectAllWords = []`

循环每个 `word`：

1. **IPA 词拼接**
   - 若 `word.phonetic` 存在：加入 `ipaWords`
   - 否则若有 `word.subwords`：把每个 `subword.subtext` 连接后加入 `ipaWords`
   - 否则加入空字符串 `""`

2. **时间戳**
   - `startTimes.push(String(word.begin || 0))`
   - `endTimes.push(String(word.end || 0))`

3. **词级正确率标签**
   - `wordScore = Number(word.score || 0)`
   - 阈值规则：`wordScore >= 8` 记 `"1"`，否则 `"0"`
   - 写入 `pairAccuracyCategory`

4. **字母级正确率串**
   - `wordText = String(word.text || "")`
   - 若存在 `subwords`：
     - 遍历每个 `subword`
     - `subwordScore >= 8` => `"1"`，否则 `"0"`
     - 取 `grapheme = subword.grapheme || subword.subtext || ""`
     - 按 `grapheme.length` 重复写入 `1/0`
   - 若无 `subwords`：
     - 用词级 `wordScore >= 8` 的 `1/0`
     - 按 `wordText.length` 重复写入
   - 每个词结束后追加一个空格分隔符 `" "`

#### G.4 最终字段组装

1. `realTranscript = sample.trim()`
2. `matchedTranscript = usertext.trim()`
3. `realTranscriptsIpa = ipaWords.join(" ").trim()`
4. `warnings = buildWarnings(result)`（根据 `audiocheck` 生成）

输出对象：

- `origin_data = result`
- `real_transcript = realTranscript ? realTranscript + "." : ""`
- `ipa_transcript = realTranscriptsIpa ? realTranscriptsIpa + "." : ""`
- `pronunciation_accuracy = pronunciation.toFixed(2)`（字符串）
- `real_transcripts = realTranscript`
- `matched_transcripts = matchedTranscript ? matchedTranscript + "." : ""`
- `real_transcripts_ipa = realTranscriptsIpa`
- `matched_transcripts_ipa = realTranscriptsIpa ? realTranscriptsIpa + "." : ""`
- `pair_accuracy_category = pairAccuracyCategory.join(" ")`
- `start_time = startTimes.join(" ")`
- `end_time = endTimes.join(" ")`
- `is_letter_correct_all_words = isLetterCorrectAllWords.join("").trim()`
- 若 `warnings` 非空，则附加 `warnings`

#### G.5 跨语言实现注意点

1. **类型统一**：最终 `pronunciation_accuracy` 保持字符串格式（两位小数）。  
2. **阈值固定**：词级与字母级均使用 `>= 8` 作为正确判定阈值。  
3. **句号策略**：`real_transcript / matched_transcripts / ipa_transcript / matched_transcripts_ipa` 都是“非空才补 `.`”。  
4. **字母串空格**：`is_letter_correct_all_words` 在词之间有空格，末尾需要 `trim`。  
5. **向后兼容**：若上游字段缺失，按 `""` / `0` 兜底，避免抛异常。  

---

## 8. 获取“只属于 speaking_pronunciation 且是草稿状态”的作业数据 API

### 8.1 草稿列表
- **URL**: `GET /api/v1/essay_gradings.json`
- **Headers**: `Authorization`
- **Query**:
  - `category=speaking_pronunciation`
  - `status=draft`
  - `page=1`
  - `count=25`

示例：

```http
GET /api/v1/essay_gradings.json?category=speaking_pronunciation&status=draft&page=1&count=25
```

- **成功响应**:

```json
{
  "success": true,
  "essay_gradings": [
    {
      "id": 999,
      "topic": "...",
      "status": "draft",
      "assignment_name": "...",
      "category": "speaking_pronunciation",
      "using_time": 123,
      "newsfeed_id": "..."
    }
  ],
  "meta": {
    "current_page": 1,
    "next_page": 2,
    "prev_page": null,
    "total_pages": 5,
    "total_count": 110
  }
}
```

### 8.2 草稿详情（进入编辑页）
- **URL**: `GET /api/v1/essay_gradings/:id.json`
- **用途**:
  - 读取 `grading.speaking_pronunciation_sentences`
  - 读取 `status`
  - 读取关联 assignment 信息

---

## 9. 建议补充的“....”接口（前端常用）

虽然你本次重点是 speaking_pronunciation，但前端联调一般还需要：

1) **Assignment 详情（按 ID）**
- `GET /api/v1/essay_assignments/:id/read.json`
- 用于编辑草稿时拿 assignment 原始信息（题干、meta、分数阈值等）

2) **作业码 Join 后路由判定**
- 当前是前端根据 `essay_assignment.category` 跳转：
  - `speaking_pronunciation` -> `/speaking_pronunciation/upload/:code`
  - 其它类别类似

3) **个人资料与权限刷新**
- `GET /api/v1/general_users/me/aienglish`
- 用于决定用户可进入哪些 category

---

## 10. 前端联调建议（避免踩坑）

### 10.1 token 处理
- 登录后一定从响应头读 `authorization`，原样放到后续 `Authorization`。
- 失效后会出现 401，前端可统一跳转登录页。

### 10.2 `success=false` 但 HTTP 200
- 部分接口（例如 assignment code 不存在、access denied）会返回 `success:false` 但状态码非 4xx。
- 前端判定必须以 `success` 字段为准，不要只看 HTTP 状态码。

### 10.3 speaking_pronunciation 草稿与提交
- “保存草稿”传 `status=draft`
- “提交”传 `status=pending`
- 进入编辑页前先拿 `essay_grading`，再补拉 `assignment/read`

### 10.4 分类值
- `speaking_pronunciation`（注意下划线）
- 列表筛选参数也必须用这个精确值

---

## 11. 可直接给前端的最小联调清单

1. `POST /general_users/sign_in.json`（拿 token）  
2. `GET /api/v1/general_users/me/aienglish`（拿权限）  
3. `GET /api/v1/essay_assignments/:code/show_only.json`（校验 code + 获取 category）  
4. `POST /api/v1/essay_assignments/:code/essay_gradings.json`（首次保存草稿/提交）  
5. `GET /api/v1/essay_gradings.json?category=speaking_pronunciation&status=draft`（草稿列表）  
6. `GET /api/v1/essay_gradings/:id.json`（草稿详情）  
7. `PUT /api/v1/essay_gradings/:id.json`（继续编辑草稿或转正式提交）  
8. `GET /api/v1/essay_assignments/:id/read.json`（编辑页 assignment 信息）

---

## 12. 当前文档边界说明

- 本文聚焦“学生端 + speaking_pronunciation 主流程”。
- teacher_review、批量 PDF、supplement practice、admin 端接口未展开。
- 若你需要，我可以在下一版补一份：
  - **OpenAPI 风格 JSON/YAML**
  - **Postman collection**
  - **错误码与异常场景矩阵**（按接口逐项列出）

