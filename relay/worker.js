// Bug-report relay for Music Video Maker — a tiny Cloudflare Worker.
//
// WHY: the app is public and has no accounts. This lets anyone press "Report a problem" and have it filed as an issue in your GitHub
// repo WITHOUT a GitHub account, while the GitHub token stays secret here (never in the app or the repo).
//
// You see reports as GitHub Issues (github.com/<repo>/issues, or the free GitHub phone app) and mark one done by CLOSING it
// (add a comment first, e.g. "Fixed in 1.4.3" — the app shows that comment to the person who reported it).
//
// Setup: see relay/README.md.  Secrets/variables expected by this Worker:
//   GITHUB_TOKEN  (secret)    a fine-grained token with ONLY "Issues: read & write" on the one repo
//   REPO          (variable)  e.g. drawsomerex/music-video-maker
const MAX_TEXT = 4000;

export default {
  async fetch(request, env) {
    const cors = { "Access-Control-Allow-Origin": "*", "Access-Control-Allow-Headers": "content-type", "Access-Control-Allow-Methods": "POST, OPTIONS" };
    const reply = (obj, status = 200) => new Response(JSON.stringify(obj), { status, headers: { ...cors, "content-type": "application/json" } });
    if (request.method === "OPTIONS") return new Response(null, { headers: cors });
    if (request.method !== "POST") return reply({ error: "POST only" }, 405);

    let data;
    try { data = await request.json(); } catch { return reply({ error: "Bad request" }, 400); }
    const text = String(data.text || "").trim().slice(0, MAX_TEXT);
    if (text.length < 5) return reply({ error: "Please describe the problem." }, 400);
    if (data.website) return reply({ ok: true, number: 0 });                      // hidden field: bots fill it in, people do not

    // Light rate limit per IP (needs a KV namespace bound as LIMITS; skipped if not configured).
    if (env.LIMITS) {
      const ip = request.headers.get("cf-connecting-ip") || "unknown";
      const key = "rl:" + ip + ":" + new Date().toISOString().slice(0, 13);
      const n = parseInt((await env.LIMITS.get(key)) || "0", 10);
      if (n >= 10) return reply({ error: "Too many reports from this connection. Please try again later." }, 429);
      await env.LIMITS.put(key, String(n + 1), { expirationTtl: 3700 });
    }

    const clean = (s, n) => String(s || "").replace(/[\r\n]+/g, " ").slice(0, n);
    const first = text.split("\n")[0].slice(0, 70);
    const body = [
      text,
      "",
      "---",
      "Reported from the app. App version: " + clean(data.version, 20) + " · macOS: " + clean(data.macos, 30) + " · Mac: " + clean(data.mac, 40),
      "Screen: " + clean(data.screen, 60),
      data.error ? "Error shown: " + clean(data.error, 300) : "",
    ].filter(Boolean).join("\n");

    const res = await fetch("https://api.github.com/repos/" + env.REPO + "/issues", {
      method: "POST",
      headers: { "authorization": "Bearer " + env.GITHUB_TOKEN, "accept": "application/vnd.github+json", "user-agent": "mvm-report-relay", "content-type": "application/json" },
      body: JSON.stringify({ title: "[User report] " + first, body, labels: ["user-report"] }),
    });
    if (!res.ok) return reply({ error: "Could not file the report right now." }, 502);
    const issue = await res.json();
    return reply({ ok: true, number: issue.number });
  },
};
