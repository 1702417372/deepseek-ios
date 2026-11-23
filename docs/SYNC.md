# 多端同步（App ↔ 网页版）保姆级步骤

同步需要一个「云端存放点」。推荐用 **Cloudflare Workers**：免费、无需服务器、5 分钟搞定。
（不想折腾服务器的话，也可以用「设置 → 数据 → 导出/导入」手动搬 JSON。）

---

## 第一步：部署同步服务（电脑浏览器操作，约 5 分钟）

1. 打开 https://dash.cloudflare.com 注册/登录（免费账号，不需要绑卡）。
2. 左侧 **Workers & Pages** → **Create** → **Create Worker** → 名字填 `deepseek-sync` → **Deploy**。
3. 进入这个 Worker → 右上 **Edit code** → 把编辑器里的默认代码全删掉 → 粘贴本仓库 `docs/sync-worker.js` 的全部内容 → **Deploy**。
4. 左侧 **Storage & Databases** → **KV** → **Create a namespace**，名字随意（例如 `deepseek-sync-kv`）。
5. 回到 Worker → **Settings** → **Variables and Secrets**：
   - **KV Namespace Bindings** → Add：Variable name 填 **`SYNC`**，选刚建的 namespace → Save。
   - **Add secret**：Name 填 **`SYNC_SECRET`**，Value 填一串你随便定的随机字符（比如 32 位字母数字）→ Save。
6. 回到 Worker 首页，复制它的地址，形如：
   `https://deepseek-sync.你的子域.workers.dev`
   **在末尾加上 `/sync`**，这就是 App 里要填的同步地址。

> 也可以不设 `SYNC_SECRET`（任何人知道地址都能读写），个人自用建议设上。

## 第二步：手机 App 里填

设置 → **多端同步**：
- **同步地址**：`https://deepseek-sync.xxx.workers.dev/sync`
- **同步密钥**：刚才的 `SYNC_SECRET`
- 打开「启动时自动同步」

点 **双向同步** → 看到「双向同步完成，当前共 N 个会话」就成功。

## 第三步：另一台设备 / 网页版

网页版（`web/index.html`）设置 → 同步 → 填**同一个地址和密钥** → 双向同步。
两边任意一边新增/修改对话，点一次双向同步，两边就一致了（按会话 id 合并，updatedAt 新的胜出）。

---

## 常见错误

| 现象 | 原因 / 处理 |
| --- | --- |
| 上传/下载失败（HTTP 401） | 同步密钥和 `SYNC_SECRET` 不一致 |
| 失败（HTTP 404） | 地址少了 `/sync`，或 Worker 没部署成功 |
| 失败（HTTP 500） | Worker 里没绑 KV（变量名必须是 `SYNC`） |
| 提示地址无效 | 必须以 `https://` 开头 |
| 网页版提示跨域 | 用本仓库的 Worker 代码（已带 CORS 头）；确认地址是 /sync |
| 同步后少会话 | 用了「上传」会覆盖云端；用「双向同步」才会合并 |

## 「上传 / 下载 / 双向同步」区别

- **上传**：把本机全部会话写到云端（覆盖云端）。
- **下载**：读云端并和本机合并，保存到本机。
- **双向同步**：先读云端合并，再写回云端 —— 日常用这个。

## 数据量与隐私

- 单次 payload 上限 25MB（Worker 里校验）；图片附件是 base64，会话多时注意体积。
- 云端只存一份 JSON，键名 `payload`，只有持有 Worker 地址 + 密钥的人能读写。
