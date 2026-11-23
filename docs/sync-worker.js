// Cloudflare Worker：DeepSeek 客户端多端同步（免费额度足够个人使用）
// 部署：Workers & Pages → Create → Worker → 粘贴本文件 → Deploy
// 然后在 App/网页版的「同步」里填：同步地址 = https://<你的worker>.workers.dev/sync
//                           同步密钥 = 自己设的一串随机字符
// 建一个 KV：Storage & Databases → KV → Create namespace（变量名 SYNC），
// 在 Worker 的 Settings → Bindings 里绑定为环境变量 SYNC。

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname !== "/sync") {
      return new Response("Not found", { status: 404 });
    }
    const key = request.headers.get("X-Sync-Key") || "";
    const bearer = (request.headers.get("Authorization") || "").replace(/^Bearer\s+/i, "");
    const secret = key || bearer;
    const expected = env.SYNC_SECRET || "";
    if (expected && secret !== expected) {
      return new Response(JSON.stringify({ error: "invalid sync key" }), {
        status: 401,
        headers: { "content-type": "application/json", ...cors() },
      });
    }
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors() });
    }
    const kvKey = "payload";
    if (request.method === "GET") {
      const stored = await env.SYNC.get(kvKey);
      return new Response(stored || JSON.stringify({ conversations: [] }), {
        status: 200,
        headers: { "content-type": "application/json", ...cors() },
      });
    }
    if (request.method === "PUT" || request.method === "POST") {
      const body = await request.text();
      if (body.length > 25 * 1024 * 1024) {
        return new Response(JSON.stringify({ error: "payload too large" }), {
          status: 413,
          headers: { "content-type": "application/json", ...cors() },
        });
      }
      JSON.parse(body); // 校验是合法 JSON
      await env.SYNC.put(kvKey, body);
      return new Response(JSON.stringify({ ok: true, bytes: body.length }), {
        status: 200,
        headers: { "content-type": "application/json", ...cors() },
      });
    }
    return new Response("Method not allowed", { status: 405, headers: cors() });
  },
};

function cors() {
  return {
    "access-control-allow-origin": "*",
    "access-control-allow-methods": "GET,PUT,POST,OPTIONS",
    "access-control-allow-headers": "Authorization,Content-Type,X-Sync-Key",
  };
}
