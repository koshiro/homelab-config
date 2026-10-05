// Monitor externo del homelab (Cloudflare Worker, plan gratuito).
// - Cada 5 min revisa los servicios públicos; avisa por Telegram tras 2 fallos seguidos y al volver.
// - Dead-man's switch: check-backups.sh (Proxmox, 08:00) hace POST /ping/check-backups; si pasan
//   más de 26 h sin ping, avisa (cubre "pve apagado o sin red", que check-backups no puede avisar).
// Estado en KV (MONITOR): se escribe solo cuando algo cambia, para quedar lejos de 1.000 escrituras/día.

const CHECKS = [
  { name: "Immich", url: "https://immich.danielriquelme.cl/api/server/ping", expect: "pong" },
  { name: "Seerr", url: "https://seerr.danielriquelme.cl/api/v1/status", expect: "version" },
  { name: "Pingvin", url: "https://pingvin.danielriquelme.cl/api/health", expect: "OK" },
  { name: "Plex", url: "https://plex.danielriquelme.cl/identity", expect: "MediaContainer" },
  { name: "noledigasanadie", url: "https://noledigasanadie.danielriquelme.cl/" },
];
const FAILS_TO_ALERT = 2;
const HEARTBEATS = { "check-backups": 26 * 3600 }; // nombre -> segundos máximos sin ping

async function probe(check) {
  try {
    const res = await fetch(check.url, {
      redirect: "manual",
      signal: AbortSignal.timeout(10_000),
      headers: { "user-agent": "homelab-monitor" },
    });
    if (res.status !== 200) return `HTTP ${res.status}`;
    if (check.expect && !(await res.text()).includes(check.expect)) return "respuesta inesperada";
    return null;
  } catch (e) {
    return e.name === "TimeoutError" ? "timeout" : String(e.message || e);
  }
}

async function telegram(env, text) {
  const res = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, {
    method: "POST",
    headers: { "content-type": "application/json" },
    body: JSON.stringify({ chat_id: env.TELEGRAM_CHAT_ID, text }),
  });
  if (!res.ok) console.error("telegram", res.status, await res.text());
}

const minutes = (ms) => Math.round(ms / 60_000);

async function runChecks(env) {
  const now = Date.now();
  const prev = (await env.MONITOR.get("state", "json")) || { services: {}, heartbeats: {} };
  const state = structuredClone(prev);
  const down = [], up = [];

  const results = await Promise.all(CHECKS.map(probe));
  CHECKS.forEach((check, i) => {
    const s = (state.services[check.name] ||= { fails: 0, down: false });
    const err = results[i];
    if (err) {
      s.fails += 1;
      s.lastError = err;
      if (!s.down && s.fails >= FAILS_TO_ALERT) {
        s.down = true;
        s.since = now;
        down.push(`${check.name} (${err})`);
      }
    } else {
      if (s.down) up.push(`${check.name} (caído ${minutes(now - s.since)} min)`);
      state.services[check.name] = { fails: 0, down: false };
    }
  });

  const messages = [];
  const allDown = CHECKS.every((c) => state.services[c.name].down);
  if (down.length && allDown) messages.push("🔴 Homelab sin conexión: no responde ningún servicio");
  else if (down.length) messages.push(`🔴 Caído: ${down.join(", ")}`);
  if (up.length) messages.push(`🟢 Volvió: ${up.join(", ")}`);

  for (const [name, maxAge] of Object.entries(HEARTBEATS)) {
    const last = Number(await env.MONITOR.get(`hb:${name}`)) || 0;
    const h = (state.heartbeats[name] ||= { late: false });
    const late = now - last > maxAge * 1000;
    if (late && !h.late) {
      messages.push(`🔴 Sin noticias de ${name} hace ${last ? Math.round((now - last) / 3_600_000) + " h" : "siempre"} (¿pve apagado o sin red?)`);
    } else if (!late && h.late) {
      messages.push(`🟢 ${name} volvió a reportar`);
    }
    h.late = late;
  }

  for (const m of messages) await telegram(env, m);
  // Escribir solo si cambió algo distinto del contador de fallos en curso
  const strip = (st) => JSON.stringify({ ...st, services: Object.fromEntries(
    Object.entries(st.services).map(([k, v]) => [k, { down: v.down, fails: Math.min(v.fails, FAILS_TO_ALERT) }])) });
  if (strip(state) !== strip(prev)) await env.MONITOR.put("state", JSON.stringify(state));
}

export default {
  async scheduled(event, env, ctx) {
    ctx.waitUntil(runChecks(env));
  },

  async fetch(request, env) {
    const url = new URL(request.url);
    const auth = request.headers.get("authorization") === `Bearer ${env.HEARTBEAT_TOKEN}`;
    const m = url.pathname.match(/^\/ping\/([\w-]+)$/);
    if (m && request.method === "POST") {
      if (!auth) return new Response("unauthorized", { status: 401 });
      if (!(m[1] in HEARTBEATS)) return new Response("unknown", { status: 404 });
      await env.MONITOR.put(`hb:${m[1]}`, String(Date.now()));
      return new Response("ok\n");
    }
    if (url.pathname === "/status" && auth) {
      return Response.json(await env.MONITOR.get("state", "json"));
    }
    return new Response("not found", { status: 404 });
  },
};
