# homelab-monitor (Cloudflare Worker)

Monitor externo: corre en Cloudflare, así que avisa aunque el homelab entero esté caído
(algo que `check-backups.sh` no puede hacer, porque corre en el mismo Proxmox).

- **Cada 5 min** revisa Immich, Seerr, Pingvin, Plex y noledigasanadie. Avisa por Telegram
  (mismo bot que Proxmox) tras 2 fallos seguidos y cuando el servicio vuelve. Si no responde
  ninguno, manda un solo aviso de "homelab sin conexión".
- **Dead-man's switch**: `check-backups.sh` hace `POST /ping/check-backups` cada mañana; si pasan
  más de 26 h sin ping, avisa.
- Todo dentro del plan Workers Free (288 ejecuciones/día de 100.000; KV ~600 lecturas y unas pocas
  escrituras al día). Si algún día se pasara un límite, la operación falla: no hay cobro.

Immich está detrás de Cloudflare Access; el monitor usa `/api/server/ping`, que tiene una
aplicación Access propia con política **Bypass** (solo responde `pong`).

## Desplegar

```bash
cd cloudflare/monitor
npx wrangler login                                  # una vez, abre el navegador
npx wrangler kv namespace create MONITOR            # copiar el id a wrangler.toml
npx wrangler deploy                                 # imprime la URL *.workers.dev
# Secretos: se leen/generan en Proxmox y van directo a wrangler (no pasan por la pantalla)
ssh root@pve '. /root/.secrets/telegram.env; printf %s "$TELEGRAM_BOT_TOKEN"' | npx wrangler secret put TELEGRAM_BOT_TOKEN
ssh root@pve '. /root/.secrets/telegram.env; printf %s "$TELEGRAM_CHAT_ID"'   | npx wrangler secret put TELEGRAM_CHAT_ID
ssh root@pve 'umask 077; t=$(openssl rand -hex 32); printf "MONITOR_URL=%s\nHEARTBEAT_TOKEN=%s\n" "<URL del deploy>" "$t" > /root/.secrets/monitor.env; printf %s "$t"' \
  | npx wrangler secret put HEARTBEAT_TOKEN
```

`/root/.secrets/monitor.env` (modo 600) es lo que usa `check-backups.sh` para el ping; si no
existe, el ping se omite. Copiarlo al vault como `vault_monitor_heartbeat_token`.

## Operar

```bash
npx wrangler tail                                   # logs en vivo
ssh root@pve '. /root/.secrets/monitor.env; curl -s -H "Authorization: Bearer $HEARTBEAT_TOKEN" $MONITOR_URL/status'   # estado guardado
```

Para agregar un servicio: sumar una entrada a `CHECKS` en `src/index.js` y `npx wrangler deploy`.
