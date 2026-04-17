# AIEnglish 学生端 API 文档（前端联调用）

适用对象：前端开发（Web / App / 小程序）

---

## 1) 业务流程

1. 登录拿 token  
2. 获取个人资料和权限  
3. 输入 Assignment Code 校验  
4. 进入 speaking_pronunciation 作业  
5. 保存草稿（`draft`）或提交（`pending`）  
6. 查询记录（默认全部状态，也可按状态筛选）

接口地址是： https://docai-dev.m2mda.com

---

## 2) 鉴权规则

- 登录接口：`POST /general_users/sign_in.json`
- 成功后从响应头取 token：`authorization`
- 后续请求头统一携带：

```http
Authorization: <authorization 原值>
```

---

## 3) API 说明（每条含示例）

### 3.1 登录

- Method: `POST`
- URL: `/general_users/sign_in.json`
- Content-Type: `application/json`

请求参数：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| general_user.email | string | 是 | 邮箱 |
| general_user.password | string | 是 | 密码 |

请求示例：

```json
{
  "general_user": {
    "email": "student@example.com",
    "password": "your_password"
  }
}
```

成功响应示例：

```json
{
  "success": true,
  "message": "Logged in successfully."
}
```

---

### 3.2 获取个人资料

- Method: `GET`
- URL: `/api/v1/general_users/me/aienglish`
- Headers: `Authorization`

请求示例：

```bash
curl "{{base_url}}/api/v1/general_users/me/aienglish" -H "Authorization: {{token}}"
```

成功响应示例：

```json
{
  "success": true,
  "user": {
    "id": 1,
    "email": "student@example.com",
    "nickname": "Tom",
    "meta": {
      "aienglish_role": "student",
      "aienglish_features_list": ["speaking_pronunciation"]
    }
  }
}
```

关键返回字段说明：

| 字段 | 类型 | 说明 |
|---|---|---|
| success | boolean | 是否成功 |
| user.id | number | 用户 ID |
| user.email | string | 邮箱 |
| user.nickname | string | 昵称 |
| user.meta.aienglish_role | string | 角色 |
| user.meta.aienglish_features_list | string[] | 可用功能列表 |

---

### 3.3 Assignment Code 校验

- Method: `GET`
- URL: `/api/v1/essay_assignments/:code/show_only.json`
- Headers: `Authorization`

请求示例：

```http
GET /api/v1/essay_assignments/abc-mnop-xyz/show_only.json
```

成功响应示例：

```json
{
  "success": true,
  "essay_assignment": {
    "id": 123,
    "code": "abc-mnop-xyz",
    "category": "speaking_pronunciation",
    "meta": {
      "speaking_pronunciation_pass_score": 60,
      "speaking_pronunciation_sentences": [{ "sentence": "I like apples." }]
    }
  }
}
```

---

### 3.4 获取 assignment 详情（编辑草稿页）

- Method: `GET`
- URL: `/api/v1/essay_assignments/:id/read.json`
- Headers: `Authorization`

请求示例：

```http
GET /api/v1/essay_assignments/123/read.json
```

---

### 3.5 首次创建作答（保存草稿/直接提交）

- Method: `POST`
- URL: `/api/v1/essay_assignments/:code/essay_gradings.json`
- Headers: `Authorization`, `Content-Type: application/json`

请求参数：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| essay_grading.status | string | 是 | `draft` 或 `pending` |
| essay_grading.grading.speaking_pronunciation_sentences | array | 是 | 句子结果数组 |

请求示例（草稿）：

```json
{
    "status": "draft",
    "grading": {
        "speaking_pronunciation_sentences": [
            {
                "sentence": "I love you",
                "ipa_transcript": "aɪ ləv ju",
                "real_transcript": [
                    "I love you"
                ],
                "transcript_translation": "",
                "score": 92.17,
                "result": {
                    "origin_data": {
                        "EvalType": "general",
                        "lines": [
                            {
                                "begin": 0,
                                "businessLevel": "1.5",
                                "end": 2.48,
                                "fluency": 99.538,
                                "integrity": 100,
                                "pronunciation": 91.937,
                                "sample": "I love you",
                                "score": 92.165,
                                "speeding": 0,
                                "standardScore": 6,
                                "usertext": "I love you",
                                "voiceSpeed": 2.4,
                                "words": [
                                    {
                                        "text": "I",
                                        "type": 2,
                                        "begin": 1.18,
                                        "end": 1.51,
                                        "volume": 9,
                                        "score": 8.839,
                                        "subwords": [
                                            {
                                                "begin": 1.18,
                                                "end": 1.51,
                                                "subtext": "aɪ",
                                                "volume": 9,
                                                "score": 8.839,
                                                "graphemelen": 1,
                                                "graphemepos": 0,
                                                "grapheme": "I"
                                            }
                                        ],
                                        "phonetic": "aɪ",
                                        "sensegroup": -1,
                                        "StressOfWord": 1,
                                        "syllables": {
                                            "sylCount": 0,
                                            "sylDetails": []
                                        }
                                    },
                                    {
                                        "text": " ",
                                        "type": 7,
                                        "begin": 0,
                                        "end": 0,
                                        "volume": 0,
                                        "score": 0,
                                        "subwords": [],
                                        "phonetic": "",
                                        "sensegroup": 0,
                                        "StressOfWord": 0,
                                        "syllables": {
                                            "sylCount": 0,
                                            "sylDetails": []
                                        }
                                    },
                                    {
                                        "text": "love",
                                        "type": 2,
                                        "begin": 1.51,
                                        "end": 1.88,
                                        "volume": 5.679,
                                        "score": 9.333,
                                        "subwords": [
                                            {
                                                "begin": 1.51,
                                                "end": 1.72,
                                                "subtext": "l",
                                                "volume": 9,
                                                "score": 9.397,
                                                "graphemelen": 1,
                                                "graphemepos": 0,
                                                "grapheme": "l"
                                            },
                                            {
                                                "begin": 1.72,
                                                "end": 1.82,
                                                "subtext": "ʌ",
                                                "volume": 7.036,
                                                "score": 9.593,
                                                "graphemelen": 1,
                                                "graphemepos": 1,
                                                "grapheme": "o"
                                            },
                                            {
                                                "begin": 1.82,
                                                "end": 1.88,
                                                "subtext": "v",
                                                "volume": 1,
                                                "score": 9.009,
                                                "graphemelen": 2,
                                                "graphemepos": 2,
                                                "grapheme": "ve"
                                            }
                                        ],
                                        "phonetic": "lʌv",
                                        "sensegroup": -1,
                                        "StressOfWord": 1,
                                        "syllables": {
                                            "sylCount": 0,
                                            "sylDetails": []
                                        }
                                    },
                                    {
                                        "text": " ",
                                        "type": 7,
                                        "begin": 0,
                                        "end": 0,
                                        "volume": 0,
                                        "score": 0,
                                        "subwords": [],
                                        "phonetic": "",
                                        "sensegroup": 0,
                                        "StressOfWord": 0,
                                        "syllables": {
                                            "sylCount": 0,
                                            "sylDetails": []
                                        }
                                    },
                                    {
                                        "text": "you",
                                        "type": 2,
                                        "begin": 1.96,
                                        "end": 2.45,
                                        "volume": 8.487,
                                        "score": 9.409,
                                        "subwords": [
                                            {
                                                "begin": 1.96,
                                                "end": 2.21,
                                                "subtext": "j",
                                                "volume": 9,
                                                "score": 9.296,
                                                "graphemelen": 1,
                                                "graphemepos": 0,
                                                "grapheme": "y"
                                            },
                                            {
                                                "begin": 2.21,
                                                "end": 2.45,
                                                "subtext": "uː",
                                                "volume": 7.974,
                                                "score": 9.522,
                                                "graphemelen": 2,
                                                "graphemepos": 1,
                                                "grapheme": "ou"
                                            }
                                        ],
                                        "phonetic": "juː",
                                        "sensegroup": -1,
                                        "StressOfWord": 1,
                                        "syllables": {
                                            "sylCount": 0,
                                            "sylDetails": []
                                        }
                                    }
                                ]
                            }
                        ],
                        "pointSystem": 100,
                        "precision": 0.1,
                        "score": 92.2,
                        "speeding": 0,
                        "standardScore": 6,
                        "version": "full 1.0",
                        "voiceSpeed": 2.4,
                        "repeat": 0
                    },
                    "real_transcript": "I love you.",
                    "ipa_transcript": "aɪ lʌv juː.",
                    "pronunciation_accuracy": "92.17",
                    "real_transcripts": "I love you",
                    "matched_transcripts": "I love you.",
                    "real_transcripts_ipa": "aɪ lʌv juː",
                    "matched_transcripts_ipa": "aɪ lʌv juː.",
                    "pair_accuracy_category": "1 1 1",
                    "start_time": "1.18 1.51 1.96",
                    "end_time": "1.51 1.88 2.45",
                    "is_letter_correct_all_words": "1 1111 111",
                    "audiobase64": "" //录音base64
                },
                "speaking_times": 1
            }
        ]
    }
}
```

---

### 3.6 更新作答（继续编辑或提交）

- Method: `PUT`
- URL: `/api/v1/essay_gradings/:id.json`
- Headers: `Authorization`, `Content-Type: application/json`

请求示例：

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

---

### 3.7 获取 essay_gradings 列表（默认全部状态，可按状态筛选）

- Method: `GET`
- URL: `/api/v1/essay_gradings.json`
- Headers: `Authorization`

Query 参数：

| 参数 | 必填 | 说明 |
|---|---:|---|
| category | 否 | 例如 `speaking_pronunciation` |
| status | 否 | `draft/pending/graded/stopped`，不传则全部状态 |
| assignment_name | 否 | 作业名模糊搜索 |
| page | 否 | 默认 1 |
| count | 否 | 默认 10 |

请求示例（全部状态）：

```http
GET /api/v1/essay_gradings.json?category=speaking_pronunciation&page=1&count=25
```

请求示例（只查草稿）：

```http
GET /api/v1/essay_gradings.json?category=speaking_pronunciation&status=draft&page=1&count=25
```

响应示例：

```json
{
  "success": true,
  "essay_gradings": [
    {
      "id": 999,
      "topic": "Read sentences",
      "created_at": "2026-04-17T10:00:00.000Z",
      "updated_at": "2026-04-17T10:10:00.000Z",
      "status": "draft",
      "assignment_name": "Pronunciation Drill",
      "category": "speaking_pronunciation",
      "using_time": 123,
      "newsfeed_id": "456"
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

`essay_gradings[]` 字段说明：

| 字段 | 类型 | 说明 |
|---|---|---|
| id | number | 记录 ID |
| topic | string | 主题 |
| created_at | string | 创建时间 |
| updated_at | string | 更新时间 |
| status | string | 状态 |
| assignment_name | string | 作业名 |
| category | string | 作业分类 |
| using_time | number | 用时（秒） |
| newsfeed_id | string \| null | 关联新闻 ID |

`meta` 字段说明：

| 字段 | 类型 | 说明 |
|---|---|---|
| current_page | number | 当前页 |
| next_page | number \| null | 下一页 |
| prev_page | number \| null | 上一页 |
| total_pages | number | 总页数 |
| total_count | number | 总数 |

---

### 3.8 获取单条 essay_grading 详情

- Method: `GET`
- URL: `/api/v1/essay_gradings/:id.json`
- Headers: `Authorization`

请求示例：

```http
GET /api/v1/essay_gradings/999.json
```

---

## 4) form-data 说明（UniSound 评分入口）

该入口常用 `multipart/form-data`。

- Method: `POST`
- URL: `/api/unisound/eval`
- Content-Type: `multipart/form-data`

字段说明：

| 字段 | 类型 | 必填 | 说明 |
|---|---|---:|---|
| text | string | 是 | 参考文本 |
| voice（或 audio） | file | 是 | 音频文件 |
| durationMs | number | 否 | 录音时长毫秒 |

请求示例：

```bash
curl -X POST "{{frontend_base_url}}/api/unisound/eval" \
  -F "text=I like apples." \
  -F "voice=@./recording.wav" \
  -F "durationMs=3200"
```

---

## 5) UniSound `handleResult` 封装要点

/**
 * 处理云知声 API 返回的结果，转换为所需格式
function handleResult(result: Record<string, unknown> | null): Record<string, unknown> | null {
    const lines = result?.lines as Array<Record<string, unknown>> | undefined;
    if (!result || !lines || lines.length === 0) {
        return null;
    }

    const firstLine = lines[0];
    const sample = (firstLine?.sample as string) ?? '';
    const usertext = (firstLine?.usertext as string) ?? '';
    const pronunciation = Number(firstLine?.score ?? 0);

    const words = ((firstLine?.words as Array<Record<string, unknown>>) ?? []).filter(
        (w) => (w?.type as number) === 2
    );

    const ipaWords: string[] = [];
    const startTimes: string[] = [];
    const endTimes: string[] = [];
    const pairAccuracyCategory: string[] = [];
    const isLetterCorrectAllWords: string[] = [];

    for (const word of words) {
        if (word.phonetic) {
            ipaWords.push(String(word.phonetic));
        } else if (Array.isArray(word.subwords) && word.subwords.length > 0) {
            const subtexts = (word.subwords as Array<Record<string, unknown>>)
                .map((sw) => String(sw?.subtext ?? ''))
                .join('');
            ipaWords.push(subtexts);
        } else {
            ipaWords.push('');
        }

        startTimes.push(String(word.begin ?? 0));
        endTimes.push(String(word.end ?? 0));

        const wordScore = Number(word.score ?? 0);
        const isCorrect = wordScore >= 8 ? '1' : '0';
        pairAccuracyCategory.push(isCorrect);

        const wordText = String(word.text ?? '');
        const subwords = word.subwords as Array<Record<string, unknown>> | undefined;
        if (subwords && subwords.length > 0) {
            for (const subword of subwords) {
                const grapheme = String(subword?.grapheme ?? subword?.subtext ?? '');
                const subwordScore = Number(subword?.score ?? 0);
                const isLetterCorrect = subwordScore >= 8 ? '1' : '0';
                for (let i = 0; i < grapheme.length; i++) {
                    isLetterCorrectAllWords.push(isLetterCorrect);
                }
            }
        } else {
            const isLetterCorrect = wordScore >= 8 ? '1' : '0';
            for (let i = 0; i < wordText.length; i++) {
                isLetterCorrectAllWords.push(isLetterCorrect);
            }
        }
        isLetterCorrectAllWords.push(' ');
    }

    const realTranscript = sample.trim();
    const matchedTranscript = usertext.trim();
    const realTranscriptsIpa = ipaWords.join(' ').trim();
    const warnings = buildWarnings(result);

    const out: Record<string, unknown> = {
        origin_data: result,
        real_transcript: realTranscript ? `${realTranscript}.` : '',
        ipa_transcript: realTranscriptsIpa ? `${realTranscriptsIpa}.` : '',
        pronunciation_accuracy: pronunciation.toFixed(2),
        real_transcripts: realTranscript,
        matched_transcripts: matchedTranscript ? `${matchedTranscript}.` : '',
        real_transcripts_ipa: realTranscriptsIpa,
        matched_transcripts_ipa: realTranscriptsIpa ? `${realTranscriptsIpa}.` : '',
        pair_accuracy_category: pairAccuracyCategory.join(' '),
        start_time: startTimes.join(' '),
        end_time: endTimes.join(' '),
        is_letter_correct_all_words: isLetterCorrectAllWords.join('').trim()
    };
    if (warnings.length > 0) out.warnings = warnings;
    return out;
}


1. 输入为空或 `lines` 为空时返回 `null`。  
2. 只处理 `lines[0]`。  
3. `pronunciation_accuracy` 输出为两位小数字符串。  
4. 词级正确阈值：`score >= 8`。  
5. 支持输出：`pair_accuracy_category`、`start_time`、`end_time`、`is_letter_correct_all_words`。  
6. 建议保留 `origin_data` 便于排查。
