# 批改包装兼容、补充练习与 PDF 修复

日期：2026-08-28。分支：`bobby-codex-backend`，最终基于 `793cd47`。
修复最初基于 `48b1a34`；提交前再次 fetch，快进合入远端新增的
`793cd47`（Doorkeeper 本机 HTTP 回调配置及翻译），无冲突、未改写远端历史。
配套前端分支：`bobby-codex`，文档 `docs/2026-08-28-grading-json-fence-fix-zh.md`。
本次交付包含配套代码、回归及本文档；提交号以 Git 历史为准。
尚未部署或更改 production 数据，不需要 migration。

## 事故与修复边界

AI 的完整结果有时被包在单反引号、Markdown 代码围栏或另一层编码字符串中。
原先部分入口直接 JSON.parse，导致网页反馈缺失、列表分数缺失、补充练习被误判为 old_data。
补充练习下载则把结构化题目当 Markdown 渲染；基础控制器还可能把异常作为 HTTP 200 返回。

此前 production 下载曾返回 `invalid byte sequence in UTF-8`，但本次没有该记录的原始内容及
production 异常堆栈。因此不能宣称已证明该条线上记录的唯一根因或完成线上验收。
本修复覆盖可复现的包装解析、错误状态、结构化 PDF 与显示编码路径；并注入同类渲染异常验证失败处理。

## 共用解析与调用方

- `AiJsonParser.parse/object`：支持 Hash/Array、普通 JSON、单/双/多反引号、可选大小写 json 标签、
  标签前空格、BOM、CRLF、只有开始围栏但内部完整的 JSON，以及最多四轮解码。
- 只剥离边界包装，不删正文反引号，不执行代码，不猜括号、分数、缺失答案或截断内容。
- `object` 拒绝数组、数字、布尔和 null。有效的 0 分、false 答案仍被保留。
- `EssayGradingsController` 的评分/Grammar/General Context、Sentence Builder 报告采用共用解析。
  General Context 的真正旧版纯文本仍可显示；损坏结构化内容不再当正文输出。
- `EssayGradingSubmissionPayloadBuilder` 使用相同解析；Sentence Builder 缺少 results 时不生成假零分。
  Speaking Essay 旧评分文字可恢复，原生 speaking_report 仍优先；不存在结果不再默认 0 分。
- 老师的评分覆盖仍优先，即使 AI 原文缺失；老师明确清空的 Grammar 数组不再回退到 AI 错误。
- `SpeakingEssay::DifyScoringClient` 的报告内容和 `EssayGradingService` 建议数量解析也接入。
  HTTP/SSE 协议封包的 JSON.parse 不改，避免把传输协议与 AI 内容混淆。

## 补充练习数据契约

### 追加：列表零分与详情不一致

原事故 assignment 的两条记录在旧列表显示 0/9、Suggestions=0，但新版详情可解析原文。
列表 API 不返回原始反馈，因此 frontend 仅修详情解析不够；旧 UI 的 0/9 默认值也会误导。

- `GET /api/v1/essay_assignments/:id` 的 payload builder 读取普通/包装/编码反馈及老师评分覆盖，
  返回正确的 `score`、`overall_score`、`full_score`、`the_full_score`；支持无 criteria 的小写字段。
- 不合法数值返回 null，不用 to_i 把错误文字变为 0；有效 0、整数、6.5 等小数保留。
- `number_of_suggestion` 按可解析原文重新计算，修复历史缓存误记为 0 的情况；
  老师明确清空或修改的 grammar 优先，Sentence Builder 排除 Correct。
- 同一 builder 缓存已解析原文，列表不新增数据库查询、不返回完整原文、不额外请求每条详情。
- 这是读取时兼容，不修改数据库、时间戳或原始 AI 内容，不重新调用 AI。
- frontend 配套移除缺失值 0/9 默认值，统一列表/排序/平均分/Excel，并保留真实零分。
- 原始文本确实已损坏或缺字段时不能恢复真实分数，返回未知而不是制造分数。

读取、保存草稿、提交都调用 `SupplementPracticeParserService`，不会出现仅网页显示恢复而提交仍失败。
必须存在非空 sections/questions，合法题型、题目文本和选项；布尔 false 是合法正确答案。

题目 ID 规则保持兼容：

- Multiple Choice/True-False：`question_<section index>_<question index>`。
- Fill in：保留原 ID；仅缺失时生成 `blank_<section index>_<question index>`。
- 不重写数据库原文；草稿/提交保存的是同样规范化后的 questions_data。
- 作答优先按稳定 ID 匹配；旧无 ID 答案仍保留原匹配路径，避免重复题干串题。

接口：

| 接口/情境 | 行为 |
| --- | --- |
| GET essay_gradings/:id/supplement_practice | 正常返回 quizTitle、sections、existing_record |
| POST .../supplement_practice/draft | 保存/更新当前用户草稿，返回原草稿 ID |
| POST .../supplement_practice/submit | 服务端按存储题目计算成绩；重复提交仍拒绝 |
| 真正旧版文字练习 | 保留 HTTP 200 + success:false + code:old_data 兼容旧客户端 |
| 损坏/不完整的结构化练习 | HTTP 422，通俗说明；不创建空草稿或空提交 |
| 补充练习缺失 | 下载 HTTP 404；读取维持既有缺失处理 |
| PDF 渲染失败 | HTTP 500 或输入无效时 422；不返回 HTTP 200 假文件 |

错误详情留在服务端日志，接口文案不包含 JSON、UTF-8、异常类名或堆栈。
基础 ApiController 的全局错误处理没有改，避免影响其他接口的既有约定。

计分附带修复：漏答的 section/问题仍计入满分，缺少 user_answer 不崩溃；空白/无效 True-False
不再等同 False。结果页、报告和计分均处理 nil/false，并按 ID 匹配重复题干。
不会批量重算历史提交的存储分数；历史已有错误计分如需修复，应单独审计并授权数据修正。

## PDF

- 下载练习不再依赖完整作文评分/General Context 成功解析。
- 结构化内容按题型绘制，保留题目、选项、说明、填空占位及正文反引号；不打印整个 JSON。
- `role=teacher` 的结构化练习 PDF 包含答案；student 版本不打印答案。
  原有公开下载/role 参数方式未改，这不是新增的权限安全边界。
- 真正旧版 Markdown 继续可以下载；不再用数字正则重排，避免损坏 3.14 等正文内容。
- 绘制前的 UTF-8 处理仅作用于显示副本，不修改题目/答案和评分依据。
- Arial 字体路径大小写修为仓库实际的 ARIAL.TTF/ARIALBD.TTF，兼容 Linux。
- 补充练习使用完成绘制后的页码方式，避免动态页脚在多页时产生无效颜色指令。
- 普通长度的题目与选项一起换页；超出整页的极长题目允许正常流式分页。
- 作文单份/ZIP 下载也返回实际失败 HTTP 状态；补充练习提交报告保留原版式。

## 验证方法

使用 Ruby 3.1.0、项目既有依赖、独立 PostgreSQL 测试数据库。
务必显式设置 RAILS_ENV=test、DATABASE_URL、TEST_VECTOR_DATABASE_URL 指向专用测试库；
不要将 production URL 用于测试。初始化器还需要本地占位 Azure 配置与测试专用 DEVISE_JWT_SECRET_KEY。
本次建库/载入 schema 只针对 `127.0.0.1:55499/codex_grading_json_test_20260828`，没有运行生产 migration。

核心新增测试：

```sh
RAILS_ENV=test PARALLEL_WORKERS=1 bundle exec ruby -rlogger bin/rails test \
  test/services/ai_json_parser_test.rb \
  test/services/grading_json_consumers_test.rb \
  test/integration/assignment_grading_summary_test.rb \
  test/integration/supplement_practice_json_compatibility_test.rb
```

覆盖解析包装、内文保真、坏结构、老师覆盖/清空 Grammar、零分、原生报告优先、重复题干、漏答、
false 答案、完整草稿/提交/结果/下载、重复提交、未登录拒绝、404/422/500、旧版文字、多页 PDF。
另外重跑学生 assignment read/403、owner共享、release score、学年过滤及回填、Sentence Puzzle 的既有回归。

追加列表修复后的最终扩大测试集：127 tests、990 assertions，0 failures / 0 errors / 0 skips。
最终两轮顺序种子 2810、2811 均通过；每轮都是 127 tests / 990 assertions。
合入远端 `793cd47` 后再以种子 2812 完整重跑：127 tests / 990 assertions 全部通过。
此前种子 2806、2807、2808 的 118 tests / 905 assertions 也通过。
新增列表接口测试通过真实 JWT 请求比较列表与详情分数（普通/单反引号/代码围栏/object/双编码），
验证历史计数修复、老师零分覆盖、未知分数及读取前后数据库属性完全不变。
包含 Essay、Speaking Essay、Speaking Conversation、Sentence Builder 的真实报告下载响应检查。
开发过程中多轮验证，不把失败轮次当作通过：最初本地缺少 JWT 测试密钥导致 401，补齐仅测试环境配置后通过；
一个新增测试使用了错误的 ZIP route，改为实际 essay_assignments 路由；四层解码测试改为明确断言过深输入抛错。
这些失败均有对应修正并重跑。测试库与 production 分离，未使用测试账号登录 production。

前端：追加列表修复后 69 项回归通过、TypeScript 通过，最终完整生产构建成功（退出码 0）。
该轮存在本机 webpack 缓存 ENOSPC 警告，未阻止构建完成。
定向 ESLint 无 error，
已有 3 个 Hook dependency warnings 不属于本次解析修复。Backend 启动仍有既有 wkhtmltopdf 路径提示、
Rswag deprecation 和重复常量 warning；本次 PDF 路径使用 Prawn，不依赖 wkhtmltopdf。

`SAVE_GRADING_PDF_FIXTURES=1` 可将合成题目 PDF 写到 `tmp/pdfs`（不提交生成物）。
已用 Poppler 渲染并逐页检查老师单页/学生多页，确认中文、反引号、选项、答案隐藏、页码及换页，
最终多页渲染无 PDF syntax warning。没有把 HTTP 200 当作 PDF 成功的唯一证据。

## 客户端、上线与回退

前端修改覆盖桌面、手机及 `mini_program=1` WebView。检查了原生小程序 dashboardgrading 的结果入口，
它通过 Web SSO 打开网页结果页；本次没有修改原生小程序仓库及其中其他 agent 的未提交改动。

本地组件/回调测试不是微信真机或 production 实际用户验收。上线需分别部署 backend 和 frontend，随后：

1. 用有权账号打开原事故的 grading，核对 Score/Grammar/General Context、左右高亮。
2. 原事故补充练习执行读取、保存、再打开、提交和下载；验证 Content-Type、PDF 文件头和可读性。
3. 教师/学生分别检查答案与成绩可见性；学生不得因修复重新出现 Forbidden。
4. 手机与微信真机点击高亮/popup，检查返回、超时/失败提示及下载实际行为。
5. 如果原记录仍有编码错误，读取服务端堆栈进一步定位，不把它静默当作无成绩/无错误。
6. 比对 assignment `435183ce-65ef-4ae8-a3fb-8fdf92c96d8c` 的列表/详情分数及建议数量。
   本地网页连接 production API 时，只部署 frontend 不会使本地 backend 修复生效。
   尚未取得该原记录的认证响应；合成接口回归通过不等于该线上记录已验收。

不自动回填/重算数据，不自动重跑收费 AI 工作流。回退只需回退本次应用代码，无数据库回滚。
既有公开报告链接、学生题目接口的答案字段/权限设计未在本次重构，不能据本次回归宣称完成安全审计。
