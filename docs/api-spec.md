# DeepSeek 官方 API 规格（2026 年 11 月版 / 含「全家桶应用 API」）

> 目标读者：写 iOS SwiftUI 客户端的工程师。本文是**规格书**，不含 Swift 实现代码，但每个 JSON/HTTP 细节都可以直接照着写 Codable 结构体。
>
> - 文档口径以 2026-11-23 抓取的官方中文文档为准（多数页面加 `.md` 后缀可直接拿到原始 Markdown，本文引用均为原文）。
> - 主协议：**OpenAI 兼容的 Chat Completions**，`POST https://api.deepseek.com/chat/completions`，`Authorization: Bearer <key>`，SSE 流式。
> - 文中标注「**文档原文**」的 JSON 是文档站原样摘录；标注「**按文档拼装**」的是按字段定义组合出的示例（字段名与取值都有出处，组合方式文档未逐字给出）。
> - 关键结论先行：**旧模型名 `deepseek-chat` / `deepseek-reasoner` 已于 2026-07-24 停止使用，思考模式默认开启**。见 §0。

---

## 目录

| 章节 | 内容 |
| --- | --- |
| §0 | 相对旧实现的迁移清单（必读） |
| §A | `GET /models` 响应字段 |
| §B | `POST /chat/completions` 请求体：思考模式、联网、阅读链接、标题、内容安全、用户元信息 |
| §C | 图片输入（最重要） |
| §D | Files API 与文档解析 |
| §E | 流式响应（SSE）完整协议 |
| §F | 语音 / OCR 独立接口 |
| §G | Swift 实现注意事项 |
| §附录 1 | 端点速查表 |
| §附录 2 | 来源 URL 一览 |
| §附录 3 | 文档没写清 / 待实测的点 |
| 末节 | Swift 侧最小实现建议 |

---

## §0 相对旧实现的迁移清单

旧代码只用了 `model + messages + stream + temperature`，模型固定 `deepseek-chat` / `deepseek-reasoner`。现在必须改的：

| # | 旧 | 新 | 依据 |
| --- | --- | --- | --- |
| 1 | `deepseek-chat` / `deepseek-reasoner` | `deepseek-flash`（V4.1-Flash）/ `deepseek-v4-pro` | 请求体 `model` 的 enum 只有这两个值；更新日志写明旧两个名字「将于三个月后（2026-07-24）停止使用」 |
| 2 | 默认非思考 | **思考模式默认开启**，effort 默认 `high`；要旧的「直接答」必须显式 `{"thinking":{"type":"disabled"}}` 或 `"reasoning_effort":"none"` | 思考模式页 |
| 3 | `temperature` 生效 | **思考模式下不生效**（不报错、静默忽略）；只要声明了联网工具 / `safety_check: high` / `title.enabled`，`temperature`、`top_p`、`frequency_penalty`、`presence_penalty`、`stop`、`seed`、`n` 全部被服务端忽略 | 构建 Chatbot「被忽略的参数」 |
| 4 | 无思维链 | `delta.reasoning_content`（与 `content` 同级） | 思考模式页 / Delta schema |
| 5 | 无工具 | `tools: [{"type":"deepseek_web_search"},{"type":"deepseek_read_url"}]`（**无需 `name` 字段**） | 联网工具页 Chat Completions 段 |
| 6 | 只有文本 | 图片走 `content` 数组的 `image_url` / `file` 块；文档走 Files API 的 `file_id` | 图像理解 / 文件解析 |
| 7 | 无引用 | 引用在 `message.annotations` / 最后一个 chunk 的 `delta.annotations`（`url_citation`） | 联网工具页 |
| 8 | 无拒答处理 | `finish_reason: "content_filter"` 表示被审核拒答，**已流式下发的正文必须由客户端丢弃** | 模型内容安全页 |
| 9 | `frequency_penalty` / `presence_penalty` | 已废弃（deprecated），传了没有效果；新 schema 里根本没有 `n` / `seed` | 请求体 schema |
| 10 | 只看 `data:` 行 | 还要处理 `: keep-alive` 注释行、`data: [DONE]`、以及「最后一个 chunk 带 `error`、没有 `[DONE]`」的失败形态 | 限速与隔离 / 联网工具页 |

一句话：**新 API 是「服务端替你跑工具」的形态。搜索、抓网页、解析文件、生成标题全在服务端完成，客户端只负责 ① 发参数 ② 渲染流式内容块 ③ 把 `server_tool_calls` 原样回传。**

---

## §A `GET /models`

```http
GET https://api.deepseek.com/models
Authorization: Bearer <API_KEY>
```

### A.1 响应结构（**文档原文**）

```json
{
  "object": "list",
  "data": [
    {
      "id": "deepseek-flash",
      "object": "model",
      "owned_by": "deepseek",
      "name": "DeepSeek-V4.1-Flash",
      "context_window": 1048576,
      "max_output_tokens": 393216,
      "input_modalities": ["text", "image"],
      "output_modalities": ["text"],
      "effort": {
        "supported_levels": ["low", "high", "max"],
        "default_level": "high"
      },
      "api_capabilities": {
        "anthropic_messages": {
          "system_prompt_update": "in-history"
        }
      }
    },
    {
      "id": "deepseek-v4-pro",
      "object": "model",
      "owned_by": "deepseek",
      "name": "DeepSeek-V4-Pro",
      "context_window": 1048576,
      "max_output_tokens": 393216,
      "input_modalities": ["text"],
      "output_modalities": ["text"],
      "effort": {
        "supported_levels": ["low", "high", "max"],
        "default_level": "high"
      },
      "api_capabilities": {
        "anthropic_messages": {
          "system_prompt_update": "leading-only"
        }
      }
    }
  ]
}
```

### A.2 字段语义（逐条确认）

| 字段 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- |
| `object`（顶层） | 是 | string | 固定 `"list"` |
| `data` | 是 | array | 模型对象数组 |
| `data[].id` | 是 | string | **用来填 `model` 参数**，当前只有 `deepseek-flash`、`deepseek-v4-pro` |
| `data[].object` | 是 | string | 固定 `"model"` |
| `data[].owned_by` | 是 | string | 固定 `"deepseek"` |
| `data[].name` | 否 | string | 展示名，如 `DeepSeek-V4.1-Flash`（可直接用于模型选择器） |
| `data[].context_window` | 否 | int | 上下文总容量（输入+输出），`1048576` = 1M |
| `data[].max_output_tokens` | 否 | int | `max_tokens` 的**可接受上限**，`393216` = 384K |
| `data[].input_modalities` | 否 | string[] | `"text"` / `"image"`；**只有 `deepseek-flash` 含 `"image"`** |
| `data[].output_modalities` | 否 | string[] | 当前恒为 `["text"]` |
| `data[].effort.supported_levels` | 是（effort 存在时） | string[] | **恰好就是 `reasoning_effort` 可传的值**，不含关闭用的 `none`。当前 `["low","high","max"]` |
| `data[].effort.default_level` | 否 | string | 未指定 effort 时的默认值，必定属于 `supported_levels` |
| `data[].api_capabilities.anthropic_messages.system_prompt_update` | 是（该对象存在时） | enum | `leading-only` / `in-history`；只影响 Anthropic 协议下「中途换 system 提示词」的行为，OpenAI 协议客户端可忽略 |

**对 Swift 的用法**：`GET /models` 可作为「校验 API Key 是否有效 + 拉模型列表 + 拿 effort 档位」的唯一入口，且**不产生费用**（官方 demo 就是这么校验 Key 的）。`context_window` / `max_output_tokens` 建议直接驱动 `max_tokens` 的输入校验，不要在客户端硬编码 1M / 384K。

来源：<https://api-docs.deepseek.com/zh-cn/api/list-models>

---

## §B `POST /chat/completions` 请求体

```http
POST https://api.deepseek.com/chat/completions
Authorization: Bearer <API_KEY>
Content-Type: application/json
Accept: text/event-stream
```

### B.0 一个「全家桶拉满」的完整请求（**按文档拼装**）

```json
{
  "model": "deepseek-flash",
  "thinking": { "type": "enabled" },
  "reasoning_effort": "high",
  "tools": [
    { "type": "deepseek_web_search" },
    { "type": "deepseek_read_url" }
  ],
  "safety_check": { "level": "high" },
  "title": { "enabled": true },
  "messages": [
    {
      "role": "latest_reminder",
      "content": "2026-11-23,星期一,新加坡,App,中文"
    },
    {
      "role": "user",
      "content": "DeepSeek V4.1 有哪些更新？参考 https://api-docs.deepseek.com/zh-cn/news/news261113"
    }
  ],
  "stream": true,
  "stream_options": { "include_usage": true },
  "max_tokens": 8192,
  "user_id": "ios-anon-7f3a9c"
}
```

请求体顶层字段全集（新 schema）：

| 字段 | 类型 | 必填 | 备注 |
| --- | --- | --- | --- |
| `model` | enum | 是 | `"deepseek-flash"` 或 `"deepseek-v4-pro"` |
| `messages` | array | 是 | minItems 1；5 种 role，见 §B.6 与 §C |
| `thinking` | object 或 null | 否 | `{"type":"enabled"|"disabled"}`，见 §B.1 |
| `reasoning_effort` | enum | 否 | `none` / `low` / `high` / `max`，见 §B.1 |
| `max_tokens` | int 或 null | 否 | 1 到 393216。**未设置时**：非思考默认 8K，思考默认 64K，`effort=max` 时 128K |
| `stream` | bool 或 null | 否 | 默认 `false`；`true` 时以 `data: [DONE]` 收尾 |
| `stream_options` | object | 否 | `{"include_usage": true}`；**必须与 `stream: true` 同时用**，否则 400 |
| `tools` | array 或 null | 否 | function 工具 + 两个 DeepSeek 服务端工具，见 §B.2 / §B.3 |
| `tool_choice` | string 或 object | 否 | `none` / `auto` / `required` / `{"type":"function",...}`；**不能指定 deepseek_web_search 或 deepseek_read_url（400）**；思考模式下不支持 `required` 和指定具体 tool（400） |
| `safety_check` | object 或 null | 否 | `{"level":"low"|"high"}`，见 §B.5 |
| `title` | object 或 null | 否 | `{"enabled":true}`，见 §B.4 |
| `response_format` | object 或 null | 否 | `{"type":"text"|"json_object"}`；**声明了联网工具时只能 text，否则 400** |
| `stop` | string 或 string[] | 否 | 最多 16 个，每个 ≤512 字节；声明联网工具 / 安全审核 / 标题时被忽略 |
| `temperature` | number | 否 | 0 到 2，默认 1；**思考模式下不生效** |
| `top_p` | number | 否 | (0,1]；`deepseek-flash` 仅思考模式生效且下限 0.95，非思考恒 1.0 |
| `logprobs` / `top_logprobs` | bool / int | 否 | 声明联网工具时**禁止**（400） |
| `user_id` | string 或 null | 否 | 自定义业务侧用户 ID，≤512 字节 UTF-8，只允许字母 / 数字 / `_` / `-`；用于内容安全、KVCache 与调度隔离 |
| `frequency_penalty` | — | 否 | **已废弃，传了也没效果** |
| `presence_penalty` | — | 否 | **已废弃，传了也没效果** |

> 旧版常见的 `n`、`seed`、`preserve_thinking`、`parallel_tool_calls`、`web_search_options` 在**新 schema 里已不存在**；其中 `web_search_options` 与联网工具同时出现会直接 400（提示「请改为在 tools 中声明工具」）。

### B.1 思考模式：`thinking` 与 `reasoning_effort`

**确切写法**（OpenAI / Chat Completions 格式）：

```json
{ "thinking": { "type": "enabled" } }
```

```json
{ "thinking": { "type": "disabled" } }
```

**取值与优先级**

| 传法 | 结果 |
| --- | --- |
| `thinking: {"type":"enabled"}` | 思考模式。**优先于** `reasoning_effort` |
| `thinking: {"type":"disabled"}` | 非思考模式。**优先于** `reasoning_effort` |
| 省略 `thinking`（或 null）+ 传 `reasoning_effort` | 模式由 effort 决定：`none` = 关闭；`low`/`high`/`max` = 开启 |
| 两者都不传 | **默认开启思考模式，effort = `high`** |

- `thinking` 是对象，`type` 必填，enum 只有 `enabled` / `disabled`。
- `reasoning_effort` 的**正式 enum 是 `["none","low","high","max"]`**（默认 `high`）。为兼容还接受 `minimal`→`low`、`medium` / `xhigh`→`high`、`ultra`→`max`。
- `/models` 里 `effort.supported_levels` 给出的档位（当前 `low/high/max`）就是 `reasoning_effort` 的合法值集合，**不含 none**。

**与 `temperature` 的冲突规则（重要，且不报错）**

1. 思考模式**不支持** `temperature`、`presence_penalty`、`frequency_penalty`。官方原文：「为了兼容已有软件，设置参数不会报错，但也不会生效。」
2. `top_p`：
   - `deepseek-flash`：**仅思考模式生效**，有效范围 `0.95`–`1.0`，低于 0.95 按 0.95 处理；非思考模式恒 1.0，传值被忽略。
   - `deepseek-v4-pro`：思考模式忽略传入值（启用工具调用时固定 0.95，否则 1.0）；非思考模式生效。
3. 除思考模式外，**只要满足任一条件**：声明了 `deepseek_web_search` / `deepseek_read_url`、`safety_check.level == "high"`、`title.enabled == true` —— 则 `temperature`、`top_p`、`frequency_penalty`、`presence_penalty`、`stop`、`seed`、`n`、`preserve_thinking`、`parallel_tool_calls` 由服务端决定，**传了就被忽略**。
4. `max_tokens` **照常生效**，但它限制的是「一轮中**每一步推理**的输出长度」，不是整轮总输出（联网一轮里模型可能推理多步）。

> Swift 建议：UI 上的「温度」滑杆在 `thinking.type == enabled`，或开启任何联网 / 安全 / 标题开关时，应置灰或加说明，否则用户以为调了却没效果。

**思维链的取与回传**

- 思考内容在响应里是 `reasoning_content`，与 `content` 同级（流式在 `delta.reasoning_content`）。
- 回传规则取决于**本次请求是否带 `tools`**：
  - **带 `tools`**：历史轮次的 `reasoning_content` **必须**完整回传，否则 **400**；且会被拼进上下文。
  - **不带 `tools`**：`reasoning_content` 不必回传，传了也会被忽略、不拼进上下文。
- 官方 demo 的做法（Messages 协议）：历史思考**一律不回传**，只在「续写」时保留本轮思考及其 `signature`。

来源：<https://api-docs.deepseek.com/zh-cn/guides/thinking_mode>

### B.2 联网搜索：`tools` 的确切写法

**Chat Completions 里只要 `type`，不要 `name`**（`name` 是 Messages / Anthropic 协议才需要的）：

```json
{
  "model": "deepseek-flash",
  "tools": [
    { "type": "deepseek_web_search" },
    { "type": "deepseek_read_url" }
  ],
  "messages": [{ "role": "user", "content": "DeepSeek V4.1 有哪些更新？" }],
  "stream": true
}
```

对照 Messages 协议（**别照抄进 Chat Completions**）：

```json
{
  "tools": [
    {"type": "deepseek_web_search", "name": "deepseek_web_search"},
    {"type": "deepseek_read_url", "name": "deepseek_read_url"}
  ]
}
```

**「深度思考搜索」要不要同时开 tools + thinking？—— 要。两者组合决定模式：**

| 声明 `deepseek_web_search` | `thinking` | 行为 |
| --- | --- | --- |
| 是 | `disabled`（关闭思考） | **联网搜索**：模型按提问搜一次或几次，并带引用作答 |
| 是 | `enabled`（开启思考） | **深度思考搜索**：模型在多步推理中自主 `search` → `open_page` → `find_in_page`，最多约 **20 次工具调用**后作答 |
| 否 | 任意 | 不搜索 |
| 只声明 `deepseek_read_url` | 任意 | 只阅读用户消息里的链接，不搜索 |

**工具声明规则（违反即 400）**

- 同一个工具**只能声明一次**（重复时错误文案为 `tools: deepseek_web_search can only be declared once`）。
- `tool_choice` **不能**指定这两个工具（错误文案 `tool_choice: deepseek_web_search cannot be forced`）；`tool_choice: "required"` 会被当作 `auto`。
- `tool_choice: "none"` 会**关闭全部工具**（包括阅读链接）。
- 不支持 `allowed_domains`、`blocked_domains`、`user_location`（错误文案 `tools: allowed_domains is not supported by deepseek_web_search`）。
- 与 `response_format` 冲突：只能是 `text`；`logprobs` / `top_logprobs` 禁止。
- 声明了这些工具时**传 `web_search_options` 会 400**。
- 服务端工具**不计费**（搜索、抓取、图片搜索都不收工具费），只收模型 Token。

**多轮怎么回传**：把 assistant 消息连同 `server_tool_calls` **原样**回传（保留 `id`、`kind`、`signature`）。若框架或网关把 `server_tool_calls` 丢了，请求仍能跑，但**之前读过的网页不再进入上下文**。

**用量**：`usage.server_tool_use = {"tool_search":N,"tool_fetch":N,"tool_image_search":N}`，全为 0 时该字段省略。

来源：<https://api-docs.deepseek.com/zh-cn/guides/web_tools>

### B.3 阅读链接：`{"type":"deepseek_read_url"}`

```json
{
  "model": "deepseek-flash",
  "tools": [{ "type": "deepseek_read_url" }],
  "messages": [
    { "role": "user", "content": "用一句话总结 https://example.com/ 的内容" }
  ]
}
```

规则：

- 只在**最后一条 user 消息**里识别 URL，重复 URL 只算一个，**最多考虑前 10 个**不同 URL，由模型决定读哪些。
- 「开启思考 + 声明了 `deepseek_web_search`」时，本轮走**深度思考搜索**，**不再单独阅读链接**；只有「关闭思考」或「只声明了 `deepseek_read_url`」时才走阅读链接。
- 阅读结果里**没有正文**：`data` 恒为空字符串，网页正文加密在 `signature` 里，**必须原样回传**才能让下一轮引用到该网页。
- 开启 `safety_check` 后，阅读结果要先过审核；未通过的网页返回 `url_not_allowed`。
- 抓取失败 `error_code`：`url_not_accessible`（读不了）/ `url_not_allowed`（不允许或被审核拦下）/ `unavailable`（服务不可用或调用未完成）。

### B.4 会话标题：`title`

**请求写法**

```json
{
  "model": "deepseek-flash",
  "title": { "enabled": true },
  "messages": [{ "role": "user", "content": "北京明天会下雨吗" }],
  "stream": true
}
```

**标题在流式响应里的位置：最后一个 chunk 的 `delta.title`**

| 协议 | 非流式 | 流式 |
| --- | --- | --- |
| Chat Completions | `message.title` | **最后一个 chunk 的 `delta.title`** |
| Messages | 顶层 `title` | `message_delta` 的 `delta.title` |
| Responses | 顶层 `title` | 结束事件的 `response.title` |

细节：

- 标题由模型「回答时顺带生成」，**无需额外请求、不计费**。
- 回答结束后，服务端**最多再等 5 秒**拿标题才结束响应 —— 这 5 秒会体现为「正文已显示完但流还没关」，UI 要能容忍。
- **不保证有标题**（拒答、出错时没有）：必须自己兜底，例如取用户消息前 N 个字符。
- 建议**只在会话第一次请求**开启，拿到标题后后续请求关掉。

来源：<https://api-docs.deepseek.com/zh-cn/guides/conversation_title>

### B.5 内容安全：`safety_check`

**请求写法**

```json
{ "safety_check": { "level": "high" } }
```

| `level` | 含义 |
| --- | --- |
| `high` | 开启基础风控：审核模型**输入与输出**（含 `tool_result` 内容、以及图片） |
| `low` | API 默认检查，等同不传 `safety_check` |
| 其它值 | **400**（`safety_check: level must be low or high`） |

**命中拒答时响应里的标识（Chat Completions）**

```json
{
  "choices": [
    {
      "index": 0,
      "message": { "role": "assistant", "content": "" },
      "finish_reason": "content_filter"
    }
  ]
}
```

- **`finish_reason` 的取值是 `"content_filter"`** —— 这就是「拒答标识」。
- `content` 为空字符串，**不返回 `annotations`**；`server_tool_calls` **保留**，但各步的思考被清空。
- **图片**被审核拦下时会指出是哪几张图，字段在 `message.refusal`（流式在**最后一个 chunk 的 `delta.refusal`**），形如
  `The following images were blocked by content moderation: messages.1.content.0`
- **输入**未通过审核：整个请求返回 **HTTP 400 `Content Exists Risk`**（不是 200 + 拒答）。
- 开启 `safety_check` 后，模型输出结束后**连接不会立即关闭**：服务端还要对完整输出做一次审核，审核期间连接保持打开，之后仍可能以拒答结束 —— 所以「看到内容了」不等于安全，必须等 `finish_reason`。
- **已流式下发的文本无法撤回**：拿到 `content_filter` 时客户端必须**删掉已展示的回答**，换成自己的拒答文案。官方 demo 的做法是把该轮的 `thinking` 与 `text` 块全部丢弃，只保留工具块。
- 拒答不会说明原因；拒答前的 Token 照常计费。
- 未开启 `safety_check` 但声明了联网工具的请求，**也可能**以拒答结束。
- 审核消耗的 Token 计入输出 Token，并单独列在 `usage.completion_tokens_details.safety_tokens`（仅 `high` 时返回）。

来源：<https://api-docs.deepseek.com/zh-cn/guides/safety>

### B.6 用户元信息标记：`latest_reminder` 消息

这不是请求顶层的参数，而是 **`messages` 里的一种 role**：

```json
{
  "role": "latest_reminder",
  "content": "2026-11-23,星期一,新加坡,App,中文"
}
```

**格式**：`<date>,<weekday>,<location>,<platform>,<language>`

| 字段 | 说明 |
| --- | --- |
| `date` | `YYYY-MM-DD` |
| `weekday` | 该日期是星期几，**用 `language` 对应的语言书写**（`Monday` / `星期一`） |
| `location` | 可选，可为空，**可包含逗号** |
| `platform` | `App` 或 `Web`（iOS 客户端填 `App`） |
| `language` | 用该语言自身书写的语言名（`English` / `中文` / `日本語` 等） |

约束：

- 必须**紧挨在它所属的 `user` 消息之前**；放在其他位置 → **400**。也不能夹在 `tool_use` 与对应的 `tool_result` 之间。
- `content` **必须是字符串**，否则请求体无法解析 → **422**；格式不符 → 400（并指出不合法字段）。
- 每一轮都可以带一条；**建议随历史一起回传**（不回传也能跑，但会降低上下文缓存命中率）。
- 这条消息里的链接**不会被阅读**，也不影响是否搜索。
- Chat Completions 与 Messages 支持；**Responses API 不支持**。
- `language` 有官方枚举（70+ 种，含 `中文`、`中文繁體`、`中文香港`、`English` 等），完整清单见来源页。

**完整示例（文档原文）**

```json
{
  "model": "deepseek-flash",
  "messages": [
    { "role": "latest_reminder", "content": "2026-11-10,星期二,新加坡,Web,中文" },
    { "role": "user", "content": "DeepSeek 是什么？" },
    { "role": "assistant", "content": "DeepSeek 是……" },
    { "role": "latest_reminder", "content": "2026-11-11,星期三,新加坡,Web,中文" },
    { "role": "user", "content": "今天有什么新闻" }
  ]
}
```

来源：<https://api-docs.deepseek.com/zh-cn/guides/latest_reminder>

---

## §C 图片输入（最重要）

### C.0 先决条件：只有 `deepseek-flash` 支持图片

| 模型 | 图像理解 | 依据 |
| --- | --- | --- |
| `deepseek-flash`（V4.1-Flash） | **支持** | `/models` 的 `input_modalities` 含 `"image"`；价格页「图像理解：支持」 |
| `deepseek-v4-pro` | **不支持** | `/models` 的 `input_modalities` 只有 `["text"]`；价格页「图像理解：不支持」 |

旧模型名 `deepseek-v4-flash-vision-exp` 仍可调用，但模型已下线，请求由最新 Flash 承接。

### C.1 方式一：Base64 内联（本地图片最常用）—— 完整 JSON（**按文档拼装，字段取文档原文**）

```json
{
  "model": "deepseek-flash",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "这张图片里有什么？" },
        {
          "type": "image_url",
          "image_url": { "url": "data:image/jpeg;base64,/9j/4AAQSkZJRgABAQ..." }
        }
      ]
    }
  ]
}
```

- `content` **从字符串变成数组**（block 数组），不再是纯字符串。
- 元素类型只有三种：`text` / `image_url` / `file`。
- `image_url.url` 既可以是 **data URL**（`data:image/jpeg;base64,<BASE64>`），也可以是 **http(s) 链接**。
- data URL 的 `data:image/jpeg` 前缀里的 MIME 只是声明；**实际格式由文件内容判断**，且必须是 JPEG / PNG / GIF / WebP 之一。
- 多图 = 多个 `image_url` 元素；文字与图片的元素顺序就是模型看到的顺序。

### C.2 方式二：外部图片 URL

```json
{
  "type": "image_url",
  "image_url": {
    "url": "https://example.com/image.jpg",
    "detail": "low"
  }
}
```

- 模型会**自己去下载**这张图，所以要求：URL 长度 ≤ **8192 字符**，图片 ≤ **32 MiB**，且 **60 秒内**下载完成。
- 链接必须可公开访问（不需要鉴权）；超长 URL 请改用 base64 或 Files API。

### C.3 方式三：Files API 的 `file_id`（复用 / 大图首选）

先 `POST /files` 上传拿到 `file_id`（形如 `file-api-xxxxxxxxxxxxxxxx`），再在 `content` 里放 `file` 块：

```json
{
  "model": "deepseek-flash",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "text", "text": "这张图片里有什么？" },
        { "type": "file", "file_id": "file-api-xxxxxxxxxxxxxxxx" }
      ]
    }
  ]
}
```

- 与内联图片不同，`file_id` 引用的单图 **最大 64 MiB**，不受 32 MiB 单图检查限制。
- 同一账号下所有 API Key 共享文件，可被任一 API 家族引用。
- 想复用同一张图、或 base64 会让请求体超过 48 MiB，就走这条路。

### C.4 `file` 块的 `file_data` 内联变体

```json
{
  "type": "file",
  "file_data": "data:image/jpeg;base64,<BASE64_DATA>",
  "filename": "image.jpg"
}
```

- `file_id` 与 `file_data` **必须二选一**：都不传 → 400（`file must have a file_id or file_data`）；都传 → 400（`file cannot have both file_id and file_data`）。
- `filename` 只在配合 `file_data` 时有效，不能与 `file_id` 同时出现。

### C.5 `detail` 字段（只对 `image_url` 有效）

| 取值 | 行为 |
| --- | --- |
| `low` | 推理前缩到 512×512，更快更省 token（不需要精细细节时用） |
| `high` | 保留原图（为兼容提供，等价 `original`） |
| `original` | 保留原图 |
| `auto` | 自动选择，**当前等价 `original`** |

```json
{ "type": "image_url", "image_url": { "url": "https://example.com/a.jpg", "detail": "low" } }
```

通过 `file_id` 传图时 `detail` 被忽略（Responses API 的 `input_image` 明确如此；Chat Completions 的 `file` 块本身没有 `detail` 字段）。

### C.6 三种 content part 的完整字段定义

| `type` | 字段 | 必填 | 类型 | 说明 |
| --- | --- | --- | --- | --- |
| `text` | `text` | 是 | string | 文本内容 |
| `image_url` | `image_url` | 是 | object | 内部只有两个字段：`url`（必填，string）、`detail`（可选，`low`/`high`/`original`/`auto`） |
| `file` | `file_id` | 二选一 | string | Files API 返回的 ID |
| `file` | `file_data` | 二选一 | string | `data:image/jpeg;base64,...` |
| `file` | `filename` | 否 | string | 仅配合 `file_data` |

### C.7 限制（官方表格，逐条照抄）

| 限制项 | 数值 |
| --- | --- |
| 支持的格式 | JPEG、PNG、GIF、WebP（由**文件实际内容**判断，不看文件名 / MIME） |
| 外部 URL 长度 | 8192 字符 |
| **请求体大小** | **48 MiB** |
| 单张图片大小上限（base64 / 外部 URL） | 32 MiB |
| 单张图片大小上限（Files API `file_id`） | 64 MiB |
| 单个请求最大图片数 | **600** |
| 单个请求图片总大小 | 不含 `file_id` 的图最多 64 MiB；包含 `file_id` 的图最高 200 MiB |
| 图片最大尺寸 | 单边最长 **8192 像素**；单请求含 **15 张及以上**图片时降为单边最长 **4096 像素** |

### C.8 使用限制

- 图片可以出现在 `user`、`system`、`tool` 消息中；**`assistant` 消息携带图片会返回 400**。
  - 注意：Chat Completions 的 `system` 消息 schema 里 `content` 只有 string 一种类型（见 §B.0），所以**OpenAI 协议下把图片放 user 消息最稳**（这条差异见附录 3）。
- 开启 `safety_check` 后，送入模型的图片会经过审核；未通过时响应以**拒答**结束，并指出是哪些图片（`message.refusal` / `delta.refusal`）。
- 图片按尺寸换算 token 并与文本一起计费：每张图进模型前会被自动缩放 —— 总像素小于约 544×544 的会保持长宽比**放大**，更大的会保持长宽比**缩小**到总像素约等于 1300×1300；因此**每张图 token 上限 1024**（2000×2000 与 5000×5000 缩放后消耗相同）。多图各自独立计算，无额外系数。

### C.9 客户端策略（推荐）

| 场景 | 建议 |
| --- | --- |
| 拍照 / 相册一次性提问 | base64 `image_url`，先压到长边 ≤ 4096 px、JPEG 质量 0.8，通常 200–600 KB |
| 同一张图会用在多轮 / 多请求 | Files API 上传一次，之后只传 `file_id` |
| 图片 > 32 MiB 或请求体逼近 48 MiB | 必须走 Files API（上限 64 MiB / 单图） |
| 只需要读图中文字、且图很大 | 先本地降采样；OCR 需求也可直接用 §F 的 OCR 接口 |
| 需要模型看细节 | 不加 `detail`（默认 `original`）；想省钱再加 `detail: "low"` |

---

## §D Files API（文件输入）

### D.1 上传：`POST /files`

```http
POST https://api.deepseek.com/files
Authorization: Bearer <API_KEY>
Content-Type: multipart/form-data; boundary=<BOUNDARY>
```

**表单字段**

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `purpose` | **是** | `user_data` / `text_recognition` / `rich_layout_recognition`（见 D.2） |
| `file` | **是** | 二进制文件 |
| `expires_after[anchor]` | 否 | 若提供必须为 `created_at`，且需与 `expires_after[seconds]` 一起用 |
| `expires_after[seconds]` | 否 | 3600 ` 2592000（1 小时 ` 30 天）。两个都不传则**永久有效** |

> **关键坑：上传文档时 `purpose` 字段必须排在 `file` 字段之前**，否则 400。图片（`user_data`）没有这个顺序要求，但统一「purpose 先、file 后」最省事。

**curl（文档原文）**

```bash
curl https://api.deepseek.com/files \
  -H "Authorization: Bearer <DeepSeek API Key>" \
  -F purpose="user_data" \
  -F file="@image.jpg"
```

**成功响应 200（文档原文）**

```json
{
  "id": "file-api-xxxxxxxxxxxxxxxx",
  "object": "file",
  "bytes": 102400,
  "created_at": 1700000000,
  "filename": "image.jpg",
  "purpose": "user_data",
  "expires_at": 1700003600
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 形如 `file-api-...`，**对话请求里引用的就是它** |
| `object` | 是 | 固定 `"file"` |
| `bytes` | 是 | 文件大小 |
| `created_at` | 是 | Unix 秒 |
| `filename` | 是 | 文件名（≤512 字节） |
| `purpose` | 是 | 枚举同上 |
| `expires_at` | 否 | 只有上传时设了有效期才出现 |

### D.2 `purpose` 与文件类型对照（决定「模型能不能看到文档里的图」）

| `purpose` | 可上传的文件 | 模型得到的内容 |
| --- | --- | --- |
| `user_data` | 图片（JPEG/PNG/GIF/WebP）；纯文本（txt、md、csv、json、代码文件等）；表格（XLSX、XLS）与电子书（EPUB、MOBI） | 图片被模型直接看到；纯文本 / 表格 / 电子书会**转成 Markdown 文本**注入上下文 |
| `text_recognition` | PDF、Word（DOC/DOCX）、PowerPoint（PPT/PPTX），以及 PNG/JPEG/WebP/GIF/BMP/TIFF 等图片 | **只有文字**；文档里的图表、照片、示意图被丢弃 |
| `rich_layout_recognition` | 同上 | **文字 + 文档里的图**：图会被裁出来，按原位与文字一起交给模型 |

- 以 `user_data` 上传 PDF / Word / PowerPoint 会返回 **400**。
- 用这两种识别 purpose 上传的文档**不能当图片用**（放进图片块 → 400）。

### D.3 在 Chat Completions 里引用（图片与文档同一个写法）

```json
{
  "model": "deepseek-flash",
  "messages": [
    {
      "role": "user",
      "content": [
        { "type": "file", "file_id": "file-api-xxxxxxxxxxxxxxxx" },
        { "type": "text", "text": "总结这份文档的要点。" }
      ]
    }
  ]
}
```

- 文档**只能通过 `file_id` 引用**，不支持在请求里直接传文件内容或文件 URL。
- 每个请求最多引用 **20 个文档**，文档文字合计 **≤ 8 MiB**；同一个 `file_id` 引用多次按多次计算；超过 → 400。
- 多轮对话中，历史消息引用的 `file_id` 文档内容会**完整保留**在上下文里；上下文超长 → 400（不会静默截断）。
- `rich_layout_recognition` 裁出的图会占输入 Token，并计入「每个请求的图片数量上限」。

### D.4 文件解析的时序（写客户端必须知道）

1. 文件**在上传过程中完成解析**，**解析成功后才返回 `file_id`** —— 所以拿到的 `file_id` 一定可用。
2. 解析期间服务端**不发送任何数据**：客户端和中间代理的超时时间要设成「上传时间 + 解析时间」。
3. 客户端中途断开时**解析仍会执行到结束**，成功的照常保存并计费（之后能在 `GET /files` 里看到）。
4. 上传失败的文件不保存、不计费。
5. **原始文件和解析结果都不支持下载**。

### D.5 纯文本 / 表格 / 电子书（`user_data`）

- txt、md、csv、json、代码文件：原样作为文本。
- XLSX、XLS、EPUB、MOBI：**上传时转换为 Markdown**。不支持 AZW3 和带 DRM 的电子书。
- 原文件最大 32 MiB，**文本内容最大 8 MiB**；这类上传**不计费**。

### D.6 列举 / 查询 / 删除

```http
GET    https://api.deepseek.com/files?after=<file_id>&limit=20&order=desc&purpose=user_data
GET    https://api.deepseek.com/files/file-api-xxxxxxxxxxxxxxxx
DELETE https://api.deepseek.com/files/file-api-xxxxxxxxxxxxxxxx
```

| 查询参数 | 说明 |
| --- | --- |
| `after` | 分页游标（file_id），返回此文件之后的文件 |
| `limit` | 1 到 1000 |
| `order` | `asc`（默认）/ `desc` |
| `purpose` | 按用途过滤 |

列表响应（文档原文）：

```json
{
  "object": "list",
  "data": [
    {
      "id": "file-api-xxxxxxxxxxxxxxxx",
      "object": "file",
      "bytes": 102400,
      "created_at": 1700000000,
      "filename": "image.jpg",
      "purpose": "user_data"
    }
  ],
  "first_id": "file-api-xxxxxxxxxxxxxxxx",
  "last_id": "file-api-xxxxxxxxxxxxxxxx",
  "has_more": false
}
```

删除响应：

```json
{ "id": "file-api-xxxxxxxxxxxxxxxx", "object": "file", "deleted": true }
```

### D.7 限制与错误

| 限制 | 数值 |
| --- | --- |
| 单个上传文件大小 | 图片 **64 MiB**；PDF/Word/PowerPoint 等文档 **100 MiB**；纯文本、表格与电子书 **32 MiB** |
| 上传时限 | 文档需 **120 秒**内传完；其他文件 **10 分钟** |
| 文件名最大长度 | 512 字节 |
| 单用户最大存储 | **25 GiB** |
| 单用户最大文件数 | **10000** |
| 文件有效期 | 1 小时到 30 天，或不传 `expires_after` 永久有效 |
| 文档页数 | 1000 页 |
| 解析时长 | 提交后 120 秒，超时 504 |
| 每账号同时进行的文档上传 | **15**（与 OCR API 分开计） |

| 状态码 | 原因 |
| --- | --- |
| 400 | 文件无法解析、格式不支持、文件有打开密码，或 `purpose` 写在 `file` 之后 |
| 408 | 上传过慢 |
| 413 | 文件过大 |
| 429 | 同时进行的文档上传数超限 |
| 500 | 解析结果不完整 |
| 503 | 服务繁忙 |
| 504 | 解析超时 |

### D.8 计费

- **上传解析时**：解析成功按**文档页数**一次性计费。
- **对话引用时**：不再收解析费；每次引用按实际拼入上下文的输入 Token 计费。

### D.9 有没有「文件解析后作为文本内联注入」的方式？

- **Chat Completions：没有**。文档只能先上传拿 `file_id` 再用 `file` 块引用。
- 想在 Chat Completions 里直接给文本，就是一个普通 `{"type":"text","text":"..."}` 内容块（也就是客户端自己把文本塞进去）。
- 只有 **Messages（Anthropic）协议**支持「不落 Files API、直接把文本当文档传」：
  ```json
  {"type": "document", "source": {"type": "text", "media_type": "text/plain", "data": "文档内容"}}
  ```

### D.10 Anthropic 兼容 Files API（如果将来切 Messages 协议）

端点位于 `/anthropic/v1/files`，且**必须**带请求头 `anthropic-beta: files-api-2025-04-14`。与 OpenAI 兼容版的差异：

| | OpenAI 兼容 | Anthropic 兼容 |
| --- | --- | --- |
| 列表分页 | `after` | `after_id` / `before_id`（互斥） |
| 列表 `limit` | 1–1000，默认 1000 | 1–1000，默认 20 |
| 列表 `order` / `purpose` | 支持 | 不支持 |
| 列表顶层 `object` | `"list"` | 无 |
| 大小字段 | `bytes` | `size_bytes` |
| 类型字段 | `object` | `type` |
| `created_at` | Unix 秒 | RFC 3339 字符串 |
| 必需请求头 | 无 | `anthropic-beta: files-api-2025-04-14` |
| `purpose` | 必填 | 可选（缺省 `user_data`） |

来源：<https://api-docs.deepseek.com/zh-cn/guides/files_api>、<https://api-docs.deepseek.com/zh-cn/guides/document_parsing>、<https://api-docs.deepseek.com/zh-cn/api/create-file>

---

## §E 流式响应（SSE）完整协议

### E.1 传输层约定

| 项 | 值 |
| --- | --- |
| 响应头 | `Content-Type: text/event-stream` |
| 行格式 | 只有 `data:` 行（Chat Completions **不发送 `event:` 行**） |
| 心跳 | 等待期间持续发送 **SSE 注释行 `: keep-alive`**（非流式请求则持续返回空行） |
| 结束 | 最后一条是 **`data: [DONE]`** |
| 失败 | 生成开始后出错时状态码已是 200；**最后一个 chunk 带 `error`、`choices` 为空数组，之后没有 `[DONE]`** |
| 超时 | 请求发出后 10 分钟仍未开始推理，服务端关闭连接 |

解析器必须做到：忽略注释行 / 空行；把多行 `data:` 用 `\n` 拼起来；只在空行处派发事件；遇到 `[DONE]` 结束。

### E.2 chunk 结构（`object: "chat.completion.chunk"`）

```json
{
  "id": "071f229d-daa0-4557-a580-106a22e8df73",
  "object": "chat.completion.chunk",
  "created": 1793084907,
  "model": "deepseek-flash",
  "system_fingerprint": "e72d3c7f663d3e1383b00b3884cb4501",
  "choices": [
    {
      "index": 0,
      "delta": { "content": "Hello" },
      "logprobs": null,
      "finish_reason": null
    }
  ],
  "usage": null
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `id` | 是 | 本次对话 ID，同一流内所有 chunk 相同 |
| `object` | 是 | 固定 `"chat.completion.chunk"` |
| `created` | 是 | Unix 秒，同一流内所有 chunk 相同 |
| `model` | 是 | 实际模型名 |
| `system_fingerprint` | 是 | 后端配置指纹 |
| `choices` | 是 | 数组；**出错时为空数组** |
| `choices[].index` | 是 | 恒 0（当前不支持 n） |
| `choices[].delta` | 是 | 增量对象，见 E.3 |
| `choices[].server_tool_event` | 否 | **DeepSeek 扩展，与 `delta` 并列（在 choice 上）**，每 chunk 最多一个，见 E.4 |
| `choices[].logprobs` | 否 | 对数概率；声明联网工具时不允许请求 |
| `choices[].finish_reason` | 是（可 null） | 结束原因，见 E.7 |
| `usage` | 否 | Token 用量；**最后一个 chunk 一定带**，见 E.5.5 |

### E.3 `delta` 的字段（全部可选）

| 字段 | 类型 | 说明 |
| --- | --- | --- |
| `role` | string | 仅首个 chunk 出现，恒 `"assistant"` |
| `reasoning_content` | string | null | **思维链增量**（仅思考模式） |
| `content` | string | null | **正文增量** |
| `tool_calls` | array | **客户端 function 工具**的增量（与本文的服务端工具无关）；第一个 chunk 带 `id`、`type`、`function.name`，后续只带 `function.arguments` 片段 |
| `annotations` | array | 引用（`url_citation`）；**流式只在最后一个 chunk 出现一次** |
| `server_tool_calls` | array | 服务端工具调用完整列表；**流式只在最后一个 chunk 出现一次**，下一轮原样回传 |
| `title` | string | 会话标题；**流式只在最后一个 chunk 出现一次** |
| `refusal` | string | 图片被审核拦截的说明；**流式只在最后一个 chunk 出现一次** |

**注意**：`reasoning_content` 与 `content` 是**同一个 delta 上的两个独立字段**，会交替出现；官方示例的循环写法是「有 `reasoning_content` 就追加思考，否则追加正文」。首 chunk 可能只有 `role` 和空 `content`。

### E.4 服务端工具的过程事件：`server_tool_event`

**位置**：`choices[0].server_tool_event`（**与 `delta` 同级**，不是在 delta 里，也不是 `tool_calls`）。一个 chunk 最多携带一个事件。

| `type` | 携带字段 | 含义 |
| --- | --- | --- |
| `step_reasoning_done` | `step` | 第 `step` 步的思考已输出完：**在此之前输出、还没归属的 `reasoning_content` 都属于这一步**。每步在它的第一次调用开始之前发送一次 |
| `call_started` | `step`、`call` | 这一步的一次调用开始，`call` 带完整的 `action` |
| `call_completed` | `step`、`call` | 调用结束，`call` 带 `status` 以及 `sources` / `page` / `error`，**不带 `signature`** |

**三个事件的示例（按文档字段拼装）**

```json
{ "type": "step_reasoning_done", "step": 0 }
```

```json
{
  "type": "call_started",
  "step": 0,
  "call": {
    "index": 0,
    "id": "srvtoolu_s_00_3f2a9c...",
    "type": "deepseek_web_search",
    "kind": "search",
    "action": { "type": "search", "queries": ["DeepSeek V4.1"] }
  }
}
```

```json
{
  "type": "call_completed",
  "step": 0,
  "call": {
    "index": 0,
    "id": "srvtoolu_s_00_3f2a9c...",
    "type": "deepseek_web_search",
    "kind": "search",
    "action": { "type": "search", "queries": ["DeepSeek V4.1"] },
    "status": "completed",
    "sources": [
      {
        "type": "url",
        "url": "https://example.com/news",
        "title": "示例新闻",
        "snippet": "……",
        "site_name": "Example News",
        "site_icon": "https://cdn.deepseek.com/site-icons/example.com",
        "published_at": "2026-10-16T16:00:00+00:00"
      }
    ]
  }
}
```

**`call` 对象字段**

| 字段 | 说明 |
| --- | --- |
| `index`、`id` | 调用在本步内的序号；`id` 与其它协议形式相同（`srvtoolu_...`） |
| `type` | 开启这项能力的工具：`deepseek_web_search` 或 `deepseek_read_url` |
| `kind` | `search` / `deep_search` / `read_link` / `image_search` / `deep_image_search` |
| `action` | `{type:"search",queries}` 或 `{type:"open_page",url}` 或 `{type:"find_in_page",url,pattern}` 或 `{type:"read_link",url}` |
| `status` | `completed` / `failed`；响应结束时还没结果的调用为 `failed` |
| `sources` | 搜索结果（展示字段同 Responses API） |
| `page` | 打开的网页或阅读的链接：`{url,title,published_at}`，**仅供展示** |
| `signature` | 加密的网页，**只有成功阅读的链接才有**（只在最后一个 chunk 的完整 `server_tool_calls` 里） |
| `error` | 失败时的 `{code}`，错误码见 §B.3 |

**关键语义**（照抄文档）：

- 思考和正文照常通过 `delta.reasoning_content` 与 `delta.content` 流式输出；**各步的思考依次输出，中间不加分隔**。要区分「这属于第几步」，靠 `step_reasoning_done` 事件切分。
- **完整的 `server_tool_calls` 与 `annotations` 只发送一次**，在带 `finish_reason` 的最后一个 chunk 的 `delta` 中 —— 所以流式渲染时，「搜索卡片」要靠 `server_tool_event` 实时画，「最终结构」要靠最后一个 chunk 补齐（尤其是 `signature`）。
- 最后一个 `step_reasoning_done` 之后输出的思考，就是最后一步的思考（它同时会出现在 `message.reasoning_content` / 非流式 `reasoning_content` 里）。

### E.5 最后一个 chunk 里有什么

> 位置：`data: {"...","choices":[{"index":0,"delta":{...},"finish_reason":"stop"}],"usage":{...}}`

| 字段 | 说明 |
| --- | --- |
| `delta.annotations` | 引用数组，见 E.6 |
| `delta.server_tool_calls` | 服务端工具调用（按「步」分组），见 E.5.2 |
| `delta.title` | 会话标题（开了 `title.enabled` 才有） |
| `delta.refusal` | 图片被拦截的说明 |
| `finish_reason` | 非 null，见 E.7 |
| `usage` | 整个请求的用量（**即使没开 `include_usage` 也有**） |

#### E.5.1 非流式响应里的对应位置

同样的字段在**非流式**响应里位于 `choices[0].message`：`message.annotations`、`message.server_tool_calls`、`message.title`、`message.refusal`、`message.reasoning_content`、`message.content`、`message.tool_calls`。

#### E.5.2 `server_tool_calls` 完整结构（**文档原文**，Chat Completions）

```json
{
  "role": "assistant",
  "reasoning_content": "资料够了，可以回答……",
  "content": "这篇文章主要讲……。作者此前在……任职。",
  "annotations": [
    {
      "type": "url_citation",
      "url_citation": {
        "url": "https://example.com/post",
        "title": "...",
        "start_index": 0,
        "end_index": 10
      }
    }
  ],
  "server_tool_calls": [
    {
      "index": 0,
      "reasoning_content": "",
      "calls": [
        {
          "index": 0,
          "id": "srvtoolu_rl_00_3f2a...",
          "type": "deepseek_read_url",
          "kind": "read_link",
          "action": { "type": "read_link", "url": "https://example.com/post" },
          "status": "completed",
          "page": { "url": "https://example.com/post", "title": "...", "published_at": "2026-01-02" },
          "signature": "q3J0b1RmZ1c4cE1x..."
        }
      ]
    },
    {
      "index": 1,
      "reasoning_content": "读完了，再查一下作者背景……",
      "calls": [
        {
          "index": 0,
          "id": "srvtoolu_s_01_9c41...",
          "type": "deepseek_web_search",
          "kind": "search",
          "action": { "type": "search", "queries": ["..."] },
          "status": "completed",
          "sources": [
            {
              "type": "url",
              "url": "https://example.com/news",
              "title": "...",
              "snippet": "...",
              "site_name": "Example News",
              "site_icon": "...",
              "published_at": "2026-01-02T03:04:05+00:00"
            }
          ]
        }
      ]
    }
  ]
}
```

结构要点：

- **两层数组**：`server_tool_calls[]` 的每个元素是**一步推理**（`{index, reasoning_content, calls[]}`），`calls[]` 里才是每次工具调用。
- 步的 `reasoning_content`：开启思考时**总是字符串**，该步没有思考时为 `""`；未开启思考时**不返回该字段**。
- `message.reasoning_content` **只包含最后一步的思考**，之前各步的思考在各自条目里。
- `message.content` 里**没有引用角标**；引用在 `message.annotations`。
- `page` 里的 `url` / `title` / `published_at` 仅供展示，回传前改它们没有影响；但 `signature` **必须原样回传**。

### E.6 引用（citations / annotations）

Chat Completions 的引用**不在正文里**，而在 `message.annotations`（流式在最后一个 chunk 的 `delta.annotations`）：

```json
{
  "annotations": [
    {
      "type": "url_citation",
      "url_citation": {
        "url": "https://example.com/post",
        "title": "示例标题",
        "start_index": 0,
        "end_index": 10
      }
    }
  ]
}
```

| 字段 | 说明 |
| --- | --- |
| `type` | 恒为 `"url_citation"` |
| `url_citation.url` | 来源 URL |
| `url_citation.title` | 标题；**未知时为 URL 本身** |
| `url_citation.start_index` / `end_index` | 按 `content` 的 **Unicode 码点**计数（不是 UTF-16，不是字节） |

- **没有引用时不返回该字段**（不是空数组）。
- 引用对应的展示信息（站点名、图标、snippet）要按 URL 去 `sources` 或 `page` 里查。
- 对比：Messages 协议的引用是「每个 `text` 块自带 `citations` 数组 + `citations_delta` 事件」；Chat Completions 是「最后一个 chunk 一次性给 `annotations`」。**这也是官方 demo（走 Messages）与 Chat Completions 最大的渲染差异。**

### E.7 `finish_reason` 取值

| 取值 | 含义 | 客户端应对 |
| --- | --- | --- |
| `stop` | 回答完成 | 正常结束 |
| `length` | 输出达到 `max_tokens` 或上下文上限，回答被截断 | 提示「已截断」，可提供「继续生成」 |
| `content_filter` | **内容审核拒答** | **丢弃已展示的思考与正文**，展示自己的拒答文案；本轮不要进上下文 |
| `tool_calls` | 模型发起了**客户端 function 工具**调用（不是服务端联网工具） | 走函数调用流程 |
| `insufficient_system_resource` | 后端推理资源不足，生成被打断 | 可重试 |
| `aborted` | 生成过程被中断 | 可重试 |

> 使用 OpenAI Python SDK 时，以 `content_filter` 或 `length` 结束会让 `get_final_completion()` 报错 —— 这是 SDK 行为，不是 HTTP 错误。

### E.8 错误帧与「200 里报错」

生成开始后出错（推理超时 / 中断等）：**HTTP 状态码已经是 200**，流以错误结束：

- 最后一个 chunk 带 `error`，`choices` 为**空数组**，**之后没有 `[DONE]`**。
- 非流式：响应体为 `{"error": {...}, "usage": {...}}`，状态码仍是 200 —— **SDK 不会抛异常，必须自己检查 `error` 字段**。

请求阶段失败的正常 HTTP 错误（非 2xx）形如：

```json
{
  "error": {
    "message": "safety_check: level must be low or high",
    "type": "invalid_request_error",
    "param": null,
    "code": "invalid_request_error"
  }
}
```

### E.9 一次「思考 + 联网搜索 + 带引用回答」的完整事件序列（**按文档描述拼装**）

文档给出的内容顺序（Messages 格式描述，Chat Completions 的语义一一对应）：

```text
（思考）        delta.reasoning_content …
（第0步结束）   server_tool_event: step_reasoning_done  step=0
（发起搜索）    server_tool_event: call_started   step=0  call.action=search(queries=[...])
（搜索完成）    server_tool_event: call_completed step=0  带 sources[]
（思考）        delta.reasoning_content …
（第1步结束）   server_tool_event: step_reasoning_done  step=1
（正文）        delta.content …
（收尾）        最后一个 chunk: delta.annotations=[url_citation...]
                              delta.server_tool_calls=[...]
                              delta.title="…"
                              finish_reason="stop"
                              usage={...}
data: [DONE]
```

一个更细的 chunk 级示例（关键行，**按文档字段拼装**）：

```text
data: {"id":"a1","object":"chat.completion.chunk","created":1795000000,"model":"deepseek-flash","system_fingerprint":"fp","choices":[{"index":0,"delta":{"role":"assistant","content":""},"logprobs":null,"finish_reason":null}],"usage":null}

data: {"id":"a1",...,"choices":[{"index":0,"delta":{"reasoning_content":"用户问的是"},"logprobs":null,"finish_reason":null}],"usage":null}

data: {"id":"a1",...,"choices":[{"index":0,"delta":{},"server_tool_event":{"type":"step_reasoning_done","step":0},"logprobs":null,"finish_reason":null}],"usage":null}

data: {"id":"a1",...,"choices":[{"index":0,"delta":{},"server_tool_event":{"type":"call_started","step":0,"call":{"index":0,"id":"srvtoolu_s_00_x","type":"deepseek_web_search","kind":"search","action":{"type":"search","queries":["DeepSeek V4.1"]}}},"logprobs":null,"finish_reason":null}],"usage":null}

data: {"id":"a1",...,"choices":[{"index":0,"delta":{},"server_tool_event":{"type":"call_completed","step":0,"call":{"index":0,"id":"srvtoolu_s_00_x","type":"deepseek_web_search","kind":"search","action":{"type":"search","queries":["DeepSeek V4.1"]},"status":"completed","sources":[{"type":"url","url":"https://example.com/a","title":"A","snippet":"…","site_name":"Example","site_icon":"https://…","published_at":"2026-10-16T16:00:00+00:00"}]}},"logprobs":null,"finish_reason":null}],"usage":null}

data: {"id":"a1",...,"choices":[{"index":0,"delta":{"content":"DeepSeek V4.1 "},"logprobs":null,"finish_reason":null}],"usage":null}

data: {"id":"a1",...,"choices":[{"index":0,"delta":{"content":"于 10 月发布。"},"logprobs":null,"finish_reason":null}],"usage":null}

data: {"id":"a1",...,"choices":[{"index":0,"delta":{"content":"","annotations":[{"type":"url_citation","url_citation":{"url":"https://example.com/a","title":"A","start_index":0,"end_index":12}}],"server_tool_calls":[{"index":0,"reasoning_content":"","calls":[{"index":0,"id":"srvtoolu_s_00_x","type":"deepseek_web_search","kind":"search","status":"completed","action":{"type":"search","queries":["DeepSeek V4.1"]},"sources":[{"type":"url","url":"https://example.com/a","title":"A"}]}]}],"title":"DeepSeek V4.1 更新"},"logprobs":null,"finish_reason":"stop"}],"usage":{"prompt_tokens":120,"completion_tokens":80,"total_tokens":200,"prompt_cache_hit_tokens":0,"prompt_cache_miss_tokens":120,"prompt_tokens_details":{"cached_tokens":0},"completion_tokens_details":{"reasoning_tokens":30},"server_tool_use":{"tool_search":1,"tool_fetch":0}}}

data: [DONE]
```

> 上例中第二个及之后的 `data:` 行用 `...` 省略了重复的 `id/object/created/model/system_fingerprint`，真实响应是完整的。

### E.10 非流式响应对照（文档原文）

```json
{
  "id": "88beaa90-17fd-45fc-939c-2ef75e2d913c",
  "object": "chat.completion",
  "created": 1793084842,
  "model": "deepseek-flash",
  "choices": [
    {
      "index": 0,
      "message": {
        "role": "assistant",
        "content": "Hello! How can I help you today?"
      },
      "logprobs": null,
      "finish_reason": "stop"
    }
  ],
  "usage": {
    "prompt_tokens": 7,
    "completion_tokens": 11,
    "total_tokens": 18,
    "prompt_tokens_details": { "cached_tokens": 0 },
    "prompt_cache_hit_tokens": 0,
    "prompt_cache_miss_tokens": 7
  },
  "system_fingerprint": "e72d3c7f663d3e1383b00b3884cb4501"
}
```

### E.11 官方 demo 的流式解析逻辑（**逐条文字化**）

> 重要前提：**官方 demo（chat-demo）走的是 Anthropic 兼容的 `POST /anthropic/v1/messages`，不是 Chat Completions。** 所以它解析的是 `content_block_*` 系列事件。它的解析思路与「什么必须容错」是最权威的参考，下面先讲它怎么做的，再给 Chat Completions 的等价映射。

**（1）SSE 字节流解码（`src/services/api/sse.ts`）**

- 自研增量解码器，按 WHATWG SSE 规范：文本先入 buffer，用 `\r\n|\r|\n` 切行；行尾的 `\r` 若正好是 buffer 末尾则**先不处理**（等下一片判断是不是 `\r\n` 的前半）。
- 以 `:` 开头的行是注释（例如 `: keep-alive`）→ **直接丢弃**。
- 字段解析：取第一个 `:` 之前为字段名，之后为值，值若以单个空格开头则去掉一个；`data` 多行用 `\n` 连接；另有 `event`、`id` 字段；`retry` 不处理。
- **空行才派发事件**；流结束时，结尾若剩一个 `\r` 视作完整换行处理，其余没有以空行结尾的事件按规范丢弃。
- `TextDecoder` 用 `{stream:true}` 解码，保证多字节字符跨分片不被截断。

**（2）HTTP 与错误处理（`src/services/api/client.ts`）**

- 请求头：`x-api-key: <key>`（DeepSeek 的 Anthropic 兼容端点，也可以用 `Authorization: Bearer`）、`Content-Type: application/json`、`Accept: text/event-stream`；**只有请求里含图片 / 文档块时才加 `anthropic-beta: files-api-2025-04-14`**。
- 拿到响应后**先检查 `Content-Type` 是否含 `text/event-stream`**，否则按「协议错误」处理（读取响应体里的 `error.message`）。
- 逐事件 `JSON.parse(data)`；解析失败且不是 `error` 事件 → **跳过**（容错）。
- 若 JSON 里有 `error.message` → 抛「stream 错误」；若事件名是 `error` → 抛错。
- 结构性校验后再 yield：无法识别的块 / delta **静默丢弃**，不影响后续内容（`readMessageEvent` 返回 `null` 就 `continue`）。
- 收到 `message_stop` 立即 `return`；**流结束却没见到 `message_stop` → 抛「interrupted」**（不猜测断流原因）。

**（3）块与增量的白名单校验（`src/services/api/parseEvent.ts`）**

- `text` 块：要求 `text` 是字符串；`citations` 若存在则必须是数组，逐项只保留 `type == "web_search_result_location"` 且 `url` 是字符串、`title` 可空 的项。
- `thinking` 块：要求 `thinking` 是字符串，`signature` 可选字符串。
- `server_tool_use` 块：要求 `id` 是字符串、`kind` ∈ {`search`, `deep_search`, `read_link`, `image_search`, `deep_image_search`}、`name` ∈ {`deepseek_web_search`, `deepseek_read_url`}、`input.action` ∈ {`search`（`queries` 为字符串数组）, `open_page`/`read_link`（`url`）, `find_in_page`（`url` + `pattern`）}。
- `web_search_tool_result` 块：要求 `tool_use_id`、`kind` ∈ 四种搜索类 kind、`content` 是数组；数组项只保留 `web_search_result`（`url` + `title` 必填，`snippet` / `site_name` / `site_icon` / `page_age` 可空）或 `web_search_tool_result_error`（`error_code` 必填）。
- `web_fetch_tool_result` 块：要求 `tool_use_id`、`kind` ∈ {`read_link`, `deep_search`}、`content` 是对象；要么是 `web_fetch_result`（`url` + `content.title` + `content.published_at` 可空），要么是 `web_fetch_tool_result_error`（`error_code`）。
- `tool_use`（客户端工具）：**不展示**，但会把该回复标记为「不可续写」。
- `delta` 白名单：`text_delta.text`、`thinking_delta.thinking`、`signature_delta.signature`、`citations_delta.citation`（且 citation 必须是合法 `web_search_result_location`）。
- `message_delta` 的 `stop_reason` 允许 `end_turn` / `max_tokens` / `tool_use` / `refusal`；`title` 可选；`usage` 必须四项 token 都是数字。

**（4）把事件合并成一条回复（`src/services/chat/reply.ts`）**

- 维护「临时块索引 → 本地块下标」的映射（因为丢弃的块不占位）。
- `content_block_start` 建块；`content_block_delta` 按块类型追加：文本拼 `text`、思考拼 `thinking`、`signature_delta` 拼 `signature`、`citations_delta` 往 `citations` 数组里塞；`content_block_stop` 记录思考块的结束时间。
- `message_delta` 更新 `stopReason`、`stopDetails` 与累计 `usage`。
- **拒答收尾**（`stop_reason: refusal`）：把该轮的 `thinking` 与 `text` 块**全部丢弃**（已下发的文本撤不回，只能由客户端丢弃），只保留工具块。
- **续写能力判定**：本轮只要出现过 `server_tool_use` / `web_search_tool_result` / `web_fetch_tool_result` 任一，就**不可续写**；拒答、工具调用后的回复也不可续写；只有「`stop_reason == max_tokens` 且有正文」或「被用户停止且有正文」才能续写。
- **历史回传**：历史思考**一律不回传**；文本块**去掉 citations**（服务端会忽略）；**只保留 `kind == read_link` 的工具块**，且 `signature` 为空的读链接块连调用带孩子一起不回传；相邻文本直接拼接，被思考或工具隔开的文本用空行（`\n\n`）连接。
- **拒答轮次不进上下文**；服务端「模板提示」文本块（`isTemplate`）也不进上下文。

**（5）附件上传（`src/services/attachments.ts` + `resizeUploadImage.ts`）**

- `purpose` 选择：**图片不传 purpose**（Anthropic 兼容端点缺省为 `user_data`）；PDF/DOC/DOCX/PPT/PPTX → `rich_layout_recognition`；其余（txt/md/csv/json/代码/XLSX/EPUB…）→ `user_data`。
- 大小校验：`user_data` 类 32 MB，其余 64 MB；单会话最多 50 个附件；**最多 3 个并发上传**（排队）。
- **图片上传前按长边 4096 px 等比缩放**（超过才缩），JPEG/WebP 沿用原格式、其他转 PNG，质量 1；文件名后缀按实际编码结果修正。4096 这个值同时覆盖了「单边 8192」和「≥15 张图时 4096」两种限制。

**（6）Chat Completions 的等价映射表（自己写 Swift 时照这张表）**

| 语义 | Messages（demo 用的） | **Chat Completions（本项目要用的）** |
| --- | --- | --- |
| 思维链增量 | `content_block_delta` / `thinking_delta.thinking` | `choices[0].delta.reasoning_content` |
| 正文增量 | `content_block_delta` / `text_delta.text` | `choices[0].delta.content` |
| 思考的加密签名 | `signature_delta.signature` | 无（Chat Completions 不暴露 `signature`，只有服务端工具块里有） |
| 工具调用开始 | `content_block_start` / `server_tool_use` | `choices[0].server_tool_event` = `call_started` |
| 工具调用结束 | `content_block_start` / `web_search_tool_result`、`web_fetch_tool_result` | `choices[0].server_tool_event` = `call_completed` |
| 引用 | 每个 `text` 块自带 `citations` + `citations_delta` | 最后 chunk 的 `delta.annotations`（`url_citation` + 码点区间） |
| 完整工具调用结构（回传用） | assistant `content` 里的块 | `delta.server_tool_calls` / `message.server_tool_calls` |
| 会话标题 | `message_delta.delta.title` | 最后 chunk 的 `delta.title` |
| 结束原因 | `message_delta.delta.stop_reason` ∈ {end_turn, max_tokens, tool_use, refusal} | `choices[0].finish_reason` ∈ {stop, length, content_filter, tool_calls, insufficient_system_resource, aborted} |
| 拒答 | `stop_reason == "refusal"` + `stop_details` | `finish_reason == "content_filter"` + 可选 `message.refusal` |
| 结束标记 | `message_stop` 事件 | `data: [DONE]` |

来源：<https://github.com/deepseek-ai/chat-demo>（`src/services/api/sse.ts`、`parseEvent.ts`、`client.ts`、`src/services/chat/reply.ts`、`src/services/attachments.ts`、`src/utils/resizeUploadImage.ts`）

---

## §F 语音 / OCR 独立接口（可选，简短）

这些是**独立接口**，与对话无关，路径在 `/v1/tools/` 下（注意：多了 `/v1` 前缀，和 `/chat/completions` 不一样）。

| 能力 | 方法与路径 | 请求格式 | 响应 |
| --- | --- | --- | --- |
| 语音识别 ASR | `POST https://api.deepseek.com/v1/tools/asr` | `multipart/form-data` | JSON |
| 语音合成 TTS（整段） | `POST https://api.deepseek.com/v1/tools/tts` | JSON | **音频二进制流**（`audio/wav` 或 `audio/pcm`） |
| 语音合成 TTS（流式） | `wss://api.deepseek.com/v1/tools/tts` | WebSocket | 二进制音频帧 |
| OCR | `POST https://api.deepseek.com/v1/tools/ocr` | `multipart/form-data` | JSON（按页） |

鉴权全部是 `Authorization: Bearer <API_KEY>`。

### F.1 ASR（语音识别）

```bash
curl https://api.deepseek.com/v1/tools/asr \
  -H "Authorization: Bearer <API Key>" \
  -F file="@speech.wav"
```

| 项 | 值 |
| --- | --- |
| multipart 字段 | **只有 `file`**（必填，带文件名） |
| 格式 | **16 位 PCM WAV** 或 **Ogg Opus**（由文件内容判断） |
| WAV 采样率 | 8000 / 16000 / 22050 / 24000 / 32000 / 44100 / 48000 Hz |
| 声道 | 单声道或双声道（双声道**只识别左声道**） |
| 大小 / 时长 | ≤ **8 MiB**，≤ **120 秒**，10 分钟内传完 |
| 语种 | 无参数，**自动识别**（支持 zh、yue、en、ja、ko、de、fr、es、pt、it、ru、ar、hi、id、vi、th、tr、ms、fil、pl、hu） |
| 流式 | **不支持**（一次发完整音频、返回完整文本） |

响应 200：

```json
{
  "request_id": "0b8c1c7e-3c0e-4d0f-9d3a-5f2a6f7e8b90",
  "text": "今天上海的天气怎么样？",
  "duration_ms": 3200
}
```

错误：400（格式不对或缺 `file`）/ 408（上传超 10 分钟）/ 413（>8 MiB）/ 429 / 503 / 504。计费按音频时长。

### F.2 TTS（语音合成）

**整段合成：`POST /v1/tools/tts`（JSON 请求体）**

```json
{
  "text": "你好，我是 DeepSeek。",
  "voice_id": "stella",
  "format": "wav",
  "filter_markdown": true
}
```

| 字段 | 必填 | 说明 |
| --- | --- | --- |
| `text` | 是 | 不能为空；≤ 10,000 个计费字符；请求体 ≤ 64 KiB |
| `voice_id` | 否 | `stella`（女声，默认）/ `tide`（男声） |
| `format` | 否 | `wav`（默认，`audio/wav`）/ `pcm`（**24 kHz、16 位、单声道**原始 PCM，`audio/pcm`） |
| `filter_markdown` | 否 | 默认 `true`，朗读前去掉 Markdown |

**响应**：音频**边合成边流式返回在响应体里**（不是 URL，也不是 base64），默认 WAV，单次最多 30 分钟音频。用法就是「把响应体当文件写」或「边收边播」。

- 没有语种参数（自动识别），**不支持调速**，不支持中断后续传。
- 如果音频已经开始返回后合成失败，响应会**中途断开** —— 客户端要把提前结束当成失败。
- 错误：400（无可读文本 / 内容审核 `Content Exists Risk`）、429、503、504。计费按字符（汉字算 2 个字符）。

**流式合成：WebSocket `wss://api.deepseek.com/v1/tools/tts`**

1. 可选查询参数 `voice_id`、`format`（默认 `pcm`，也可以是 `opus`；`opus` 返回不带容器的 Opus 数据包，不能直接存成 Ogg）。
2. 鉴权两种：请求头 `Authorization: Bearer <key>`，或子协议 `Sec-WebSocket-Protocol: tts, bearer.<key>`。
3. 客户端发 JSON 文本消息 `{"event":"text","text":"..."}` 分段送文本，最后发 `{"event":"finish_text"}`。
4. 服务端用**二进制消息**下发音频；会话以文本消息 `{"event":"finish","code":"success","message":"..."}` 结束，`code` 也可能是 `invalid_input` / `content_filter` / `input_timeout` / `service_error`。
5. 限制：60 秒没收到文字就结束；单会话 ≤30 分钟；≤10,000 计费字符 / 64 KiB；服务端每 25 秒 ping 一次。

### F.3 OCR

```bash
curl https://api.deepseek.com/v1/tools/ocr \
  -H "Authorization: Bearer <API Key>" \
  -F purpose="text_recognition" \
  -F file="@document.pdf"
```

| 项 | 值 |
| --- | --- |
| multipart 字段 | `file`（必填，带文件名）+ `purpose`（必填）；**传其他字段会 400** |
| `purpose` | `text_recognition`（不含图的 Word/PPT 直接提取文字，其他逐页识别）/ `rich_layout_recognition`（所有文件都逐页识别） |
| 文件类型 | PDF、Word（DOC/DOCX）、PowerPoint（PPT/PPTX）、PNG/JPEG/WebP/GIF/BMP/TIFF |
| 限制 | ≤100 MiB、≤1000 页、上传 120 秒内（停顿 ≤30 秒）、总时长 180 秒 |
| 与对话关系 | **文件不存入 Files API，也不交给对话模型** |

响应 200：

```json
{
  "id": "ocr-9b2f4c1e-5d7a-4e3b-8f21-6c0a9d4e7b12",
  "object": "ocr.result",
  "created": 1762790000,
  "purpose": "text_recognition",
  "page_count": 2,
  "pages": [
    { "index": 0, "text": "…", "finish_reason": "stop" },
    { "index": 1, "text": "…", "finish_reason": "length" }
  ],
  "usage": { "input_tokens": 1536, "output_tokens": 412, "total_tokens": 1948 }
}
```

**两个必须知道的坑**：

1. 识别过程中服务端**持续发送换行符**保持连接，识别完成后才给一个 JSON；换行属于 JSON 前导空白，**整个响应体可以直接按 JSON 解析**。
2. 识别开始后状态码就是 **200**，失败时响应体是 `{"error":{"message":"OCR did not finish in time","type":"gateway_timeout_error",...}}` —— **必须检查 `error` 字段**，不能只看状态码。

- 逐页识别结果里保留 `<｜ref｜>…<｜/ref｜><｜box｜>[[52, 40, 948, 96]]<｜/box｜>` 这类特殊标记与坐标；坐标 `[[x1,y1,x2,y2]]` 以页面左上角为原点、按页面宽高归一化到 0–1000。
- 计费：每 1000 页 1.5 元；并发上限 15（与文档上传分开计）。

来源：<https://api-docs.deepseek.com/zh-cn/guides/asr>、<https://api-docs.deepseek.com/zh-cn/guides/tts>、<https://api-docs.deepseek.com/zh-cn/guides/ocr>

---

## §G Swift 实现注意事项

### G.1 SSE 读取：用 `URLSession.bytes(for:)`

- 首选 `URLSession.bytes(for:delegate:)` 拿 `URLSession.AsyncBytes`，逐行消费。它对 `\n` 切行、自动处理 `\r\n`、跨分片的多字节 UTF-8 也不会截断，正好适合「一行一个 JSON」的 Chat Completions。
- 不要用 `data(for:)` / `dataTask`：那要等整个响应结束才回调，等于没有流式。
- 若必须用 delegate（老代码 / 需要在后台线程）：`URLSessionDataDelegate.urlSession(_:dataTask:didReceive:)` 里把 Data 追加进自建 buffer，自己按 `\r\n|\r|\n` 切行 —— 参考官方 demo 的 `ServerSentEventDecoder`（见 §E.11），注意「行尾单个 `\r` 可能是下一个 `\r\n` 的前半，要等下一片再判断」。
- **不要**用 `JSONDecoder` 直接解整段响应；也**不要**假设每个 TCP 分片正好是一条 SSE 事件。
- `bytes.lines` 会把空行作为空字符串交给你 —— 这正是 SSE 的「事件派发」信号，别把空行过滤掉；注释行以 `:` 开头，要跳过。

### G.2 流式解析的状态机

一次响应里按顺序可能出现：`role` →（`reasoning_content` 若干）→（`server_tool_event` 若干）→（`content` 若干）→ 最后一个带 `finish_reason` 的 chunk（内含 `annotations` / `server_tool_calls` / `title` / `usage`）→ `data: [DONE]`。

- **判断结束用 `finish_reason` 加 `[DONE]`，不要用「收到空 content」**：思考阶段 `content` 一直是空或缺失。
- **不要在收到 `[DONE]` 前就 finish 掉 `AsyncThrowingStream`**；反之，若流在 `[DONE]` 之前结束且没拿到 `finish_reason`，应报「连接中断」。
- **error 帧**：`choices` 为空数组加顶层 `error` → 抛错；此时不会再有 `[DONE]`。
- **`: keep-alive` 注释**只是保活；它能让 `timeoutIntervalForRequest` 不被触发，所以别把它当数据。

### G.3 JSON 解码：宁可宽松，不要严格

- 服务端会加字段、加枚举值。Swift 的 `Decodable` 默认忽略未知字段（安全），但**枚举不要用裸 String 枚举**，否则遇到新值（例如未来新增 `finish_reason`）会整条解码失败 —— 用 String 接、再在业务层 switch，或给枚举加 unknown 兜底。
- `server_tool_calls` / `annotations` / `sources` / `server_tool_event` 都是**文档只给了 object 的扩展结构**：建议用通用 JSON 值类型（AnyCodable 式）或手写宽松结构体，**不要**要求所有字段都在。
- `usage` 里的字段分「必然有」（`prompt_tokens` / `completion_tokens` / `total_tokens` / `prompt_tokens_details` / `prompt_cache_hit_tokens` / `prompt_cache_miss_tokens`）和「可选」（`completion_tokens_details.reasoning_tokens` / `safety_tokens` / `server_tool_use.*`）。
- `delta` 里大量字段是可空：`content`、`reasoning_content`、`finish_reason` 都可能是 null；`delta` 本身也可能是空对象（只带 `server_tool_event` 的 chunk）。
- `annotations` 的 `start_index` / `end_index` 按 **Unicode 码点**计数 —— Swift 里对应 `String.unicodeScalars` 的下标，**不是** `String.Index`，也**不是** utf16 偏移。用 `Array(content.unicodeScalars)` 或 `unicodeScalars.index(_:offsetBy:)` 换算，再映射回可显示的 `String.Index`。

### G.4 multipart 上传（Files API / OCR / ASR）

- 手写 multipart：`--<boundary>` 开界、每个 part 先 `Content-Disposition: form-data; name="..."`（文件再加 `; filename="..."`）与可选的 Content-Type，然后空行、内容、CRLF，最后 `--<boundary>--` 收界。
- **字段顺序**：上传文档时 `purpose` 必须排在 `file` **之前**（服务端是流式读表单的）。图片也建议统一这个顺序。
- Content-Type 必须带 `boundary`（`multipart/form-data; boundary=<BOUNDARY>`）；**不要**让 URLSession 自己生成。
- 大文件用 `URLSession.upload(for:fromFile:)`（先落盘成临时文件）而不是 `from: Data`，避免一次把 100 MiB 读进内存。
- **超时要放宽**：文档上传要「上传 + 解析」都算在内（解析最长 120 秒），OCR 总时长 180 秒。`timeoutIntervalForRequest` 建议 ≥300 秒，或给上传任务单独用一个宽松的 URLSessionConfiguration。
- 文件名含中文时不要自己拼转义，统一 UTF-8；或直接把文件名 ASCII 化（服务端只把它当展示名）。
- 记住 **同一个 `file_id` 可以无限次引用**，历史消息复用时不要重复上传；但图片超过尺寸限制时要重新上传（demo 用 4096 px 作为上限，见 §C.7）。

### G.5 base64 图片体积控制（最容易翻车的点）

服务端三条硬限制叠在一起：**单张图 32 MiB、请求体 48 MiB、单请求图片总大小 64 MiB（不含 file_id 的图）**。base64 会膨胀约 **4/3**，所以实际可用的原始图片总大小约 36 MiB，再扣掉文本与 JSON 开销。

- 上传前统一降采样：长边 ≤ **4096 px**（官方 demo 的值；文档允许 8192，但 ≥15 张图时会降到 4096，且像素多了模型也会缩到约 1300×1300 的等效像素，纯属浪费带宽）。
- iOS 侧常见坑：相册的 **HEIC/HEIF** 服务端**不支持**，必须先转成 JPEG；`UIImage.jpegData(compressionQuality:)` 会**丢掉 EXIF 方向**，要么先按方向重绘，要么只在已正确朝向的图上转换。
- 4 MB 的原图压到质量 0.8 通常 300–800 KB，够用；需要 OCR 级清晰度时用 0.9 且保持原分辨率（注意 32 MiB 上限）。
- 一次发多张图时，先在客户端累计「编码后字节数」，超过约 36 MiB 就改用 Files API，不要等 413。
- 只要同一张图会出现在多轮里，就直接走 Files API（`file_id` 不受 32 MiB 限制，且不占请求体）。

### G.6 请求超时与「静默期」

- `timeoutIntervalForRequest` 是**相邻数据之间的空闲超时**，不是总时长；开启联网搜索后服务端会持续发 `: keep-alive`，所以正常不会触发。
- 但**首个字节可能很慢**（思考 + 多次搜索）。建议 `timeoutIntervalForRequest = 60`（配合 keep-alive 足够），`timeoutIntervalForResource = 600`（对齐官方「10 分钟未开始推理就断连」）。
- 开 `title.enabled` 时，回答完成后还会**多等最多 5 秒**才结束流 —— 不要在这 5 秒里误判「卡住」而重试。

### G.7 取消、后台与重连

- 用户点「停止」：取消 Task 加 `URLSessionTask.cancel()`；`AsyncThrowingStream` 的 `onTermination` 里也要取消底层 task，否则连接泄漏。
- iOS 进后台会挂起 socket，流基本必断：**不要尝试断点续传**（没有 event id 机制），恢复前台后提示「已中断，可重新生成」。
- 官方明确：**用过 `deepseek_web_search` 或 `deepseek_read_url` 的回复不能续写**（会 400），只能重发上一次请求。所以「继续生成」按钮只对「因 `length` 截断」或「用户手动停止」的普通回复开放。
- 自动重试只对 429 / 5xx / 网络错误做，且要退避；**400 / 402 / 422 不要重试**（参数或余额问题）。

### G.8 上下文拼装（多轮最容易写错的地方）

- 每轮都要携带**完整历史**，并把上一轮的 assistant 消息**原样回传**，尤其要保留 `server_tool_calls`（含 `signature`）。
- 只要请求里带 `tools`（哪怕本轮模型没调用），历史 assistant 的 `reasoning_content` 就**必须回传**，否则 400。最稳的做法：把 assistant 消息整体保存、整体回传（content 加 reasoning_content 加 server_tool_calls 加 annotations 都留着），由服务端决定忽略哪些。
- 拒答（`content_filter`）的轮次**不要放进上下文**。
- `latest_reminder` 消息建议随历史一起保留（缓存命中率更高），它必须紧挨着对应的 user 消息。
- `file_id` 文档内容会**完整保留**在上下文里，长文档多轮很容易爆 1M 上下文 —— 要有「移除附件」的入口。

### G.9 界面状态与渲染

- 一个回复至少有 5 种可渲染实体：**思考块**、**搜索/抓取卡片（call 加 sources/page）**、**正文**、**引用角标**、**拒答**。建议客户端模型就用「块数组」（demo 是 ReplyBlock 数组），不要只有 String。
- 流式正文建议**节流刷新 UI**（例如 50–100 ms 合并一次、或按行合并），每收到一个 token 就触发一次 SwiftUI 重绘会掉帧；Markdown 渲染尤其贵（demo 专门做了节流渲染）。
- `annotations` 的 `start_index` / `end_index` 只在**整段正文收齐后**才可靠（按最终 content 的码点计数），所以引用角标建议在 finish 之后统一插入，不要边流边插。
- 拒答时**必须清空已显示内容**（流已发出撤不回），并展示自己的合规文案。

### G.10 时间 / 地区 / 语言（`latest_reminder`）

- 日期与星期用**设备本地时区**算（demo 注释明确写了「避免 UTC 日期跨日」），星期用 `Locale` 格式化成对应语言（中文给「星期一」，英文给 Monday）。
- `platform` 固定传 `App`（网页端才是 `Web`）。
- `location` 允许为空、允许含逗号；不确定位置时传空字段即可，别编造。
- 拼串不能有空格：`2026-11-23,星期一,新加坡,App,中文`。

### G.11 网络与合规

- ATS：**只能用 https**；用户自定义 base URL 时校验 scheme，否则 iOS 直接拦。
- 不要在日志里打 API Key；不要把它放进 UserDefaults（用 Keychain）。
- 如果要上架或对外提供服务，官方要求开启 `safety_check: high`，并自行承担内容安全审核、大模型登记、AI 标识等义务（原文如此）。

---

## §附录 1 端点速查表

| 用途 | 方法 | 路径 | 请求体 | 响应 |
| --- | --- | --- | --- | --- |
| 模型列表 | GET | `https://api.deepseek.com/models` | — | JSON |
| 对话补全（流式） | POST | `https://api.deepseek.com/chat/completions` | JSON | SSE `text/event-stream` |
| 对话补全（非流式） | POST | `https://api.deepseek.com/chat/completions` | JSON | JSON |
| 上传文件 | POST | `https://api.deepseek.com/files` | multipart/form-data | JSON |
| 列出文件 | GET | `https://api.deepseek.com/files` | — | JSON |
| 查询文件 | GET | `https://api.deepseek.com/files/{file_id}` | — | JSON |
| 删除文件 | DELETE | `https://api.deepseek.com/files/{file_id}` | — | JSON |
| 语音识别 | POST | `https://api.deepseek.com/v1/tools/asr` | multipart/form-data | JSON |
| 语音合成（整段） | POST | `https://api.deepseek.com/v1/tools/tts` | JSON | 音频二进制 |
| 语音合成（流式） | WSS | `wss://api.deepseek.com/v1/tools/tts` | WebSocket 文本帧 | 二进制音频帧 |
| OCR | POST | `https://api.deepseek.com/v1/tools/ocr` | multipart/form-data | JSON（可能有 error） |
| 余额查询 | GET | `https://api.deepseek.com/user/balance` | — | JSON |
| 对话（Anthropic 协议） | POST | `https://api.deepseek.com/anthropic/v1/messages` | JSON | SSE message_* |
| 对话（Responses 协议） | POST | `https://api.deepseek.com/responses` | JSON | SSE response.* |
| 前缀续写（Beta） | POST | `https://api.deepseek.com/beta/chat/completions` | JSON | 同 Chat Completions |

> 注：Search / Fetch 两个独立接口（给 Agent/RAG 用）见 <https://api-docs.deepseek.com/zh-cn/guides/search>，本文未展开，因为对话内的联网已由 `deepseek_web_search` 覆盖。

---

## §附录 2 来源 URL 一览

| # | 内容 | URL |
| --- | --- | --- |
| 1 | 构建 Chatbot（总览、协议表、被忽略参数、合规） | <https://api-docs.deepseek.com/zh-cn/guides/build_a_chatbot> |
| 2 | 联网工具（tools 写法、server_tool_calls、server_tool_event、annotations、finish_reason） | <https://api-docs.deepseek.com/zh-cn/guides/web_tools> |
| 3 | 思考模式（thinking / reasoning_effort / temperature 规则 / reasoning_content） | <https://api-docs.deepseek.com/zh-cn/guides/thinking_mode> |
| 4 | 图像理解（三种传图方式、detail、限制） | <https://api-docs.deepseek.com/zh-cn/guides/vision> |
| 5 | Files API（上传、purpose、限制、Anthropic 兼容差异） | <https://api-docs.deepseek.com/zh-cn/guides/files_api> |
| 6 | 文件解析（purpose 选择、file_id 引用、限制、计费） | <https://api-docs.deepseek.com/zh-cn/guides/document_parsing> |
| 7 | 会话标题（title、delta.title） | <https://api-docs.deepseek.com/zh-cn/guides/conversation_title> |
| 8 | 用户元信息标记（latest_reminder 格式与约束） | <https://api-docs.deepseek.com/zh-cn/guides/latest_reminder> |
| 9 | 模型内容安全（safety_check、拒答、refusal） | <https://api-docs.deepseek.com/zh-cn/guides/safety> |
| 10 | 语音识别 | <https://api-docs.deepseek.com/zh-cn/guides/asr> |
| 11 | 语音合成 | <https://api-docs.deepseek.com/zh-cn/guides/tts> |
| 12 | OCR | <https://api-docs.deepseek.com/zh-cn/guides/ocr> |
| 13 | Chat Completions API 参考（全字段 schema） | <https://api-docs.deepseek.com/zh-cn/api/create-chat-completion> |
| 14 | 模型列表 API 参考 | <https://api-docs.deepseek.com/zh-cn/api/list-models> |
| 15 | 上传文件 API 参考 | <https://api-docs.deepseek.com/zh-cn/api/create-file> |
| 16 | OCR / TTS / ASR API 参考 | <https://api-docs.deepseek.com/zh-cn/api/ocr>、<https://api-docs.deepseek.com/zh-cn/api/tts>、<https://api-docs.deepseek.com/zh-cn/api/asr> |
| 17 | 模型与价格（1M 上下文 / 384K 输出 / 多模态支持矩阵） | <https://api-docs.deepseek.com/zh-cn/quick_start/pricing> |
| 18 | 限速与隔离（并发、user_id、keep-alive、10 分钟断连） | <https://api-docs.deepseek.com/zh-cn/quick_start/rate_limit> |
| 19 | 全家桶应用 API 发布公告（2026-11-13） | <https://api-docs.deepseek.com/zh-cn/news/news261113> |
| 20 | 官方开源 demo（实现参考） | <https://github.com/deepseek-ai/chat-demo> |
| 21 | demo 关键文件 | `src/services/api/sse.ts`、`parseEvent.ts`、`client.ts`、`types.ts`、`src/services/chat/reply.ts`、`latestReminder.ts`、`src/services/attachments.ts`、`src/utils/resizeUploadImage.ts` |
| 22 | demo 在线体验 | <https://cdn.deepseek.com/chat-demo> |

> 技巧：文档站每个页面都有 **`.md` 版本**（例如 <https://api-docs.deepseek.com/zh-cn/guides/web_tools.md>），拿到的是原始 Markdown，比抓 HTML 干净得多。

---

## §附录 3 文档没写清 / 待实测的点

1. **function 工具能否与 `deepseek_web_search` 混用**：`tools` schema 说「function 加两个服务端工具」，但错误文案又有「other tools cannot be used together with deepseek_web_search, deepseek_read_url, safety_check or title yet」。**保守做法：不要混用**；要 function 工具就别同时声明服务端联网工具。
2. **`reasoning_content` 回传要求与联网工具是否互斥**：思考模式文档说「带 tools 就必须回传 reasoning_content，否则 400」；而联网工具的 Chat Completions 多轮示例**只回传了 content 加 server_tool_calls**（没有 reasoning_content）。两者可能针对不同工具类型。**保守做法：整条 assistant 消息原样回传**。
3. **`server_tool_event` 与空 delta**：文档说它是 choice 上的字段，但没给完整 JSON 样例；当 chunk 只带事件时 delta 是空对象还是被省略、`call_started` 的 call 里有没有 status，均未写明（§E.4 示例是按字段定义拼的）。**解析时要允许 delta 缺失或为空对象。**
4. **Chat Completions 下 system 消息能否带图**：图像理解页说图片可出现在 user / system / tool 消息；但 Chat Completions 的 system 消息 schema 里 content 只有 string。**保守做法：图片只放 user 消息。**
5. **`finish_reason` 与 `[DONE]` 的次序**：文档只说流以 `data: [DONE]` 结尾、失败时「最后一个 chunk 带 error 且之后没有 [DONE]」，没明确「拒答时是否也发 [DONE]」。**保守做法：以 finish_reason 为准，[DONE] 只当传输结束信号。**
6. **`include_usage` 的语义细节**：「不设置时，除最后一个块外其余块不含 usage 字段」（注意是**不含字段**而非 null），但示例里首块是 `"usage":null`。**解码时 usage 要按可选处理，且允许 null。**
7. **图片 token 的精确换算公式**：只给了「缩放到约 1300×1300 等效像素、每图上限 1024 token」和官方计算器，没有可实现的像素到 token 公式。**不要自己精确预测 token**，用 `usage` 回读。
8. **`latest_reminder` 的 language 枚举**是否强校验：给了长清单，但只说「格式不符返回 400 并指出字段」，未说明传清单外的语言名会不会 400。**照清单传。**
9. **`GET /models` 的 `effort.supported_levels` 是否含 none**：明确说**不包含**；但 `reasoning_effort` 又接受 none。UI 上「关闭思考」应走 `thinking.type = disabled`（更明确），而不是依赖 none。
10. **旧模型名是 400 还是静默路由**：更新日志说 `deepseek-chat` / `deepseek-reasoner`「2026-07-24 停止使用」，但没说现在请求会返回什么错误码。**直接迁移到 deepseek-flash，不要试探。**
11. **`deepseek-v4-pro` 是否支持联网工具**：价格页明确「图像理解：不支持」；联网工具页只说「请使用 deepseek-flash 模型」。**联网与图片能力一律用 deepseek-flash。**
12. **TTS/ASR/OCR 的限速细节**：只给了并发上限（TTS/ASR 50、OCR 15、文档上传 15）与 429，没有 Retry-After 头等细节。**退避重试。**

---

## Swift 侧最小实现建议

1. **先把模型 ID 换掉**：`deepseek-flash`（要图片、联网、标题、安全全用它），需要纯文本更强推理再用 `deepseek-v4-pro`。`deepseek-chat` / `deepseek-reasoner` 已停用。
2. **启动时先 `GET /models` 校验 Key 并缓存模型元数据**（`context_window`、`max_output_tokens`、`effort.supported_levels`、`input_modalities`），用它驱动模型选择器与 `max_tokens` 上限，不要硬编码。
3. **显式管理思考开关**：默认（不传）是「思考开启 + effort=high」。UI 要给三态：关闭（`{"thinking":{"type":"disabled"}}`）、标准（enabled 加 low）、深度（enabled 加 high 或 max），而不是只有一个开关。
4. **想清楚什么时候停用 temperature**：思考模式、开联网、开 `safety_check: high`、开 `title` 时它都不生效，UI 应置灰；保留字段也行，但别让用户以为有效。
5. **请求用 Encodable 全量字段加 encodeIfPresent**：`thinking`、`tools`、`safety_check`、`title`、`stream_options`、`reasoning_effort`、`user_id` 都做成可选，未启用就**整个 key 不出现**（而不是传 null），减少服务端兼容风险。
6. **流式用 `URLSession.bytes(for:)` 加 AsyncThrowingStream**：外层 `for try await line in bytes.lines`；跳过以 `:` 开头的注释；空行派发；`data: [DONE]` 结束；`choices` 为空且带 error 就抛错。
7. **解码层做「宽容结构体」**：delta 全字段可选、`finish_reason` 用 String 而非枚举、`server_tool_event` / `server_tool_calls` / `annotations` / `sources` 用通用 JSON 值或宽松结构体，未知字段与未知枚举值一律不崩。
8. **客户端消息模型必须是「块数组」**：思考块、搜索卡片（call 加 sources）、抓取卡片（call 加 page）、正文、引用、拒答各一种，不要只存一个拼接后的 String；否则多轮回传与 UI 渲染都会丢信息。
9. **`server_tool_calls` 原样存、原样回传**，尤其别丢 `signature`（阅读链接的网页正文全靠它复原）；丢了请求还能跑，但模型「忘了」读过的网页。
10. **assistant 消息整条回传**（content 加 reasoning_content 加 server_tool_calls 加 annotations）：既满足「带 tools 必须回传 reasoning_content」的硬要求，也避免自己判断哪些该丢。
11. **拒答要能「撤回」**：收到 `finish_reason == "content_filter"` 时清空该轮已渲染的思考与正文、展示自己的合规文案，且**该轮不进上下文**；图片被拦时读 `delta.refusal` / `message.refusal` 提示具体哪张图。
12. **引用在 finish 之后统一插入**：`annotations[].url_citation` 的 `start_index`/`end_index` 是按最终 content 的 **Unicode 码点**算的，用 unicodeScalars 换算；展示信息（站点名、图标、snippet）按 URL 去 `sources`/`page` 里查。
13. **标题只在首轮请求开**：`title: {"enabled": true}`，从最后一个 chunk 的 `delta.title` 取；**必须兜底**（失败时用用户首条消息前 N 字），并给「拿标题最多多等 5 秒」留出 UI 状态。
14. **多轮到上下文的裁剪要基于真实 usage**：用最后一次 `usage.total_tokens` 累加判断是否会撞 1M 上限（尤其带 `file_id` 文档时），不要用字符数估算；超长时提示用户移除附件或开新会话。
15. **图片走一条固定降采样管线**：HEIC 转 JPEG、按 EXIF 方向重绘、长边 ≤4096、质量 0.8，编码后统计字节数；单请求累计超过约 36 MiB 或需要复用时改走 Files API（`file_id` 上限 64 MiB 每张）。**不要**直接把相册原图 base64。
16. **multipart 手写时把 `purpose` 放在 `file` 前面**，Content-Type 带上 boundary，大文件用 upload(fromFile:)，上传与解析超时给到 300 秒以上（文档解析最长 120 秒）。
17. **每个会话每条 user 消息前插一条 `latest_reminder`**（本地时区日期 + 本地化星期 + 地区 + App + 语言），并随历史保留；格式严格为「date,weekday,location,platform,language」，中间不能有空格。
18. **取消、后台、重试要有明确策略**：取消要连底层 URLSessionTask 一起取消；后台挂起导致断流就提示重新生成（没有续传）；只对 429、5xx、网络错误退避重试，400/402/422 直接暴露给用户；用过服务端工具的轮次**不要**提供「继续生成」。
19. **UI 节流**：流式正文合并刷新（50–100 ms 或按行），Markdown 渲染单独节流；思考、搜索卡片、正文分区渲染，避免整棵视图树每个 token 重算。
20. **把 `safety_check: high` 作为默认开启项**（若对外提供服务），并准备好「输入被拒 → 400 Content Exists Risk」和「输出被拒 → content_filter」两条路径的文案。


