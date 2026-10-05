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

Si algún servicio revisado se pone detrás de Cloudflare Access, su URL de chequeo necesita una
aplicación Access con política Bypass (si no, el monitor recibe el 302 al login y lo da por caído).

## Desplegar

Publicado en `https://monitor.danielriquelme.cl` (Custom Domain). Los cron triggers exigen que la
cuenta tenga subdominio workers.dev (`danielriquelme.workers.dev`), aunque el Worker no se publica ahí.

Se usa el token de administración del vault (`vault_cloudfare_full_api_token`; el de
`vault_cloudflare_api_token` es solo R2). Node de Homebrew puede fallar: usar `bunx`.

```bash
cd cloudflare/monitor
export CLOUDFLARE_API_TOKEN=$(cd ../../ansible && ansible-vault view vars/vault.yml | sed -n 's/^vault_cloudfare_full_api_token: *//p' | tr -d "\"' ")
bunx wrangler@latest deploy
# Secretos: de Proxmox directo a wrangler (no pasan por la pantalla)
ssh root@pve '. /root/.secrets/telegram.env; printf %s "$TELEGRAM_BOT_TOKEN"' | bunx wrangler@latest secret put TELEGRAM_BOT_TOKEN
ssh root@pve '. /root/.secrets/telegram.env; printf %s "$TELEGRAM_CHAT_ID"'   | bunx wrangler@latest secret put TELEGRAM_CHAT_ID
ssh root@pve '. /root/.secrets/monitor.env; printf %s "$HEARTBEAT_TOKEN"'     | bunx wrangler@latest secret put HEARTBEAT_TOKEN
```

`/root/.secrets/monitor.env` (modo 600, `MONITOR_URL` y `HEARTBEAT_TOKEN`) es lo que usa
`check-backups.sh` para el ping; si no existe, el ping se omite.

Nota: KV es eventualmente consistente (una clave leída como inexistente queda en caché ~60 s en
ese punto de presencia); con ejecuciones cada 5 min no afecta al conteo de fallos.

## Operar

```bash
bunx wrangler@latest tail                                   # logs en vivo
ssh root@pve '. /root/.secrets/monitor.env; curl -s -H "Authorization: Bearer $HEARTBEAT_TOKEN" $MONITOR_URL/status'   # estado guardado
```

Para agregar un servicio: sumar una entrada a `CHECKS` en `src/index.js` y `bunx wrangler@latest deploy`.
