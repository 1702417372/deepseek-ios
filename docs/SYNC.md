# 多端同步（App ↔ 网页版）

两端共用一套协议和 JSON 格式，自建一个 Cloudflare Worker 即可（免费）。

## 部署同步服务（5 分钟）

1. 打开 https://dash.cloudflare.com → Workers & Pages → Create → Worker，粘贴 `docs/sync-worker.js`，Deploy。
2. Storage & Databases → KV → Create namespace，名字随意。
3. Worker → Settings → Variables → KV Namespace Bindings：变量名 `SYNC`，选中刚建的 namespace。
4. 同一页加一个 Secret：变量名 `SYNC_SECRET`，值设成你自己的随机密钥（例如 32 位字母数字）。
5. 记下 Worker 地址，拼成 `https://<你的worker>.workers.dev/sync`。

## 在客户端填写

- iOS App：设置 → 多端同步 → 同步地址 + 同步密钥 →「双向同步」，可开「启动时自动同步」。
- 网页版：设置 → 同步 → 同样的地址和密钥 →「双向同步」。

## 数据怎么走

- 上传：PUT 整份 JSON（`X-Sync-Key` 鉴权），覆盖云端。
- 下载：GET 整份 JSON。
- 双向：先 GET 合并（同会话 id 保留 updatedAt 较新的），再 PUT 合并结果。
- 导出/导入：设置 → 数据，导出 JSON 可以手动搬到另一台设备导入；格式与网页版一致。
