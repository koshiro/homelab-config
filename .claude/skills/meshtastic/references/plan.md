# Plan: reinstalación limpia de la flota (acordado 2026-10-18)

Estado: marcar `[x]` al cerrar cada paso. La fase en curso es la primera con pasos sin marcar.

## Decisiones (2026-10-18)

| Tema | Decisión | Por qué |
|------|----------|---------|
| Firmware | nightly **2.8.2.fad52bb** fijo (develop, 2026-10-17), archivado con md5 | arreglos de firma en relays, USB serial ESP32-S3, S&F, NodeDB sobre la 2.8.1 alpha |
| Vigilancia | revisión semanal de commits/releases; aviso por Telegram solo si hay razón para cambiar de build | el nightly se reemplaza a diario y no tiene notas |
| Frecuencia | **pública** ANZ LONG_FAST (slot 20, primario sin nombre + `AQ==`) + canal secundario privado | poder hablar con otros en emergencias y que nodos públicos retransmitan |
| Llaves | nacen en cada nodo (instalación limpia, IDs nuevos) | tras un reset, reprovisionar es un solo comando y no hay llaves privadas fuera del nodo |
| Canal privado | PSK nueva de 32 B, `use_aead true`, `position_precision 32` | máxima protección; la posición sale por el canal de índice más bajo con precisión > 0 |
| Homelab | AcevedoRoof por WiFi + MeshMonitor | el cable USB a pve es solo de energía (verificado: no enumera) |

## Fase 1: preparar (Claude, ~1 h)

- [x] `mt.py fw` con soporte para nightly (`nightly.meshtastic.org`) y archivo local; bajar fad52bb de las 4 placas.
- [ ] Archivar fad52bb para el Laptop y el segundo tracker (hardware por confirmar; el nightly rota a diario).
- [x] `flota.yaml` con el diseño nuevo (sin IDs; canales y perfiles) y `mt.py provisionar <nodo>`:
      región → llaves → anotar id/pubkey en flota.yaml → canales → perfil → admin_key → respaldo.
- [x] Corregir `arquitectura.md`, `recetas.md` (orden admins primero) y el PR #118.

## Fase 2: canario (CarTracker, 15 min + 24–48 h)

- [ ] Flashear limpio + `provisionar CarTracker` (sin admin_key todavía: se agregan en la fase 3).
- [ ] Verificar: GPS, posición solo por el canal privado, nodos públicos visibles, batería, estabilidad USB.

## Fase 3: admins (Dnto_L1, laptop, AcevedoRoof; ~45 min)

- [ ] Flashear y provisionar los tres; sus pubkeys quedan en `flota.yaml` → `admins`.
- [ ] AcevedoRoof: bajarlo del techo una vez (full erase por USB), WiFi + reserva DHCP, de vuelta arriba.
- [ ] `aplicar` en CarTracker para agregarle los 3 admin_key.

## Fase 4: resto (CatTracker, segundo tracker, extras; ~15 min c/u)

- [ ] Flashear y provisionar cada uno (ya nacen con admin_key).

## Fase 5: ajuste (~30 min)

- [ ] Favoritos en AcevedoRoof (toda la flota). Firma `BALANCED` en todos.
- [ ] Probar admin remoto: Mac → TCP techo → `--dest` a un tracker.
- [ ] Respaldo de todos.

## Fase 6: homelab (1–2 h, PR)

- [ ] MeshMonitor en k3s (Flux, contrato de apps), fuente TCP al techo, nodo virtual solo LAN/tailnet,
      UI tras Cloudflare Access.

## Fase 7: vigilancia (~1 h, PR)

- [ ] CronJob semanal en k3s: commits de develop y releases desde el build fijado; aviso por Telegram (bot de
      Alertmanager) si hay release nueva, el build fijado fue revocado, o commits que tocan placas/funciones de la
      flota (esp32s3, nrf52, T1000-E/LR1110, Wio L1, XIAO, Heltec tracker, firma, PKC, TRACKER, CLIENT_BASE, crash).
- [ ] Al llegar un aviso: Claude estudia los commits, decide y anota en `firmware.md`.
