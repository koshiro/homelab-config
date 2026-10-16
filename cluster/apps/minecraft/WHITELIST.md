# Whitelist

Activa y obligatoria (`ENABLE_WHITELIST` / `ENFORCE_WHITELIST` en `deployment.yml`). La lista vive en `/data/whitelist.json`; **no** se define en el manifiesto.

## Java vs Bedrock

El servidor está en `online-mode=false`:

- **Java**: UUID offline calculado desde el nombre → `whitelist add <nombre>`.
- **Bedrock** (Geyser + Floodgate): entran como `.<gamertag>` con UUID derivado del XUID de Xbox (`00000000-0000-0000-0009-…`). `whitelist add .Nombre` genera un UUID **incorrecto** y nunca coincide → usar `fwhitelist add <gamertag>` (sin el punto), que consulta el XUID.
- Los operadores (`ops.json`) entran aunque no estén en la lista.

## Bot de Telegram (`whitelist-bot/`)

Deployment aparte (`minecraft-whitelist-bot`) que lee `logs/latest.log` del NFS (solo lectura) y usa RCON por el Service interno `minecraft-rcon`:

- Avisa cuando alguien fuera de la lista intenta entrar, con botones **Agregar** / **Ignorar** (un aviso por nombre cada 15 min).
- Comandos: `/whitelist`, `/agregar <nombre>` (Bedrock con «.»), `/quitar <nombre>`, `/ayuda`.
- Solo responde al chat configurado (`TELEGRAM_CHAT_ID`). Secreto: `whitelist-bot/secret.sops.yaml` (lo aplica Flux por `solo-flux/`).
- Usa el mismo bot que las alertas de Proxmox (solo `sendMessage` allí); este deployment es el único que consume `getUpdates`, por eso `replicas: 1`.

## Limitación de online-mode=false

Nadie verifica la identidad de los jugadores Java: quien conozca un nombre de la lista puede usarlo. Bedrock sí está autenticado por Xbox. Ver opciones en `docs/PENDIENTES.md` (plugin de login / modo híbrido).
