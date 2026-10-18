---
name: meshtastic
description: Administrar la flota Meshtastic de Daniel (trackers del auto y mascotas, nodo del techo AcevedoRoof, nodo personal Dnto_L1, nodo del laptop, extras) por CLI, USB, TCP o admin remoto PKC - estado, respaldo, diff/aplicar contra flota.yaml, flasheo y full erase, firmware 2.8.x, presets LoRa, canales, admin keys, MeshMonitor y MQTT del homelab, y vigilar releases y changelogs. Usar SIEMPRE que la tarea toque Meshtastic, un nodo LoRa o el comando `meshtastic`, antes de correr el CLI a ciegas o buscar en la web.
---

# Meshtastic

Objetivo: operar la flota con pocas llamadas y **sin romper la malla**. El estado deseado está en `flota.yaml`; los
datos estables en `references/`. Primera llamada casi siempre: `$T estado` (o `$T upstream` si la tarea es
actualizar).

```bash
T=~/.claude/skills/meshtastic/mt.py   # ejecutable; su shebang usa el python del CLI (pipx venv meshtastic)
$T puertos                         # radios por USB
$T estado [--port X|--host IP]     # firmware, rol, preset, canales (sin PSK), admin keys con nombre, nodos oídos
$T respaldo [--port X|--host IP]   # .yaml + .cfg (con llave privada) en ~/.config/meshtastic-fleet/backups (600)
$T diff <nodo> [--dest !id]        # nodo vs flota.yaml + el comando `meshtastic` que lo corrige
$T aplicar <nodo> [--dest !id] [--apply]   # canales → --set (una transacción) → dueño; dry-run por defecto
$T provisionar <nodo> [--apply]   # recién flasheado: región → llaves → id/pubkey a flota.yaml → aplicar → respaldo
$T secretos [--generar-canal]     # qué secretos faltan (sin valores); crea nombre + PSK del canal privado
$T fw <nodo> [--solo-bajar]       # baja y archiva (md5) el firmware fijado, nightly o release; imprime pasos
$T upstream [--marcar]             # releases nuevas de firmware, CLI (master y PyPI) y MeshMonitor
meshtastic --port X --info | --get lora | --set k v | --dest !id --set k v | --export-config f.cfg
```

## Mapa (una tarea → dónde mirar)

| Tarea | Primero |
|-------|---------|
| **Plan en curso (reinstalación limpia)** | `references/plan.md`: primera fase sin marcar |
| ¿Qué tiene / cómo está un nodo? | `$T estado`; remoto: `$T diff <nodo> --dest !id` |
| Cambiar un ajuste en uno o todos | editar `flota.yaml` → `$T diff` → `$T aplicar --apply`; regla de orden abajo |
| Flashear, nodo nuevo o tras un reset | receta *instalación limpia* en `references/recetas.md` |
| Firmware 2.8: qué cambió, trampas | `references/firmware.md` |
| Flags del CLI, admin remoto, sesión PKC | `references/cli.md` |
| Por qué está armado así (roles, canales, admin, homelab) | `references/arquitectura.md` |
| MeshMonitor / nodo del techo en el homelab | `references/arquitectura.md` § Homelab + skill **homelab** |
| ¿Salió algo nuevo? | `$T upstream`; leer las notas de lo NUEVO, anotar en `firmware.md`, `--marcar` |

## Reglas que evitan romper la malla

- **Respaldo antes de tocar**: `$T respaldo`. Las instalaciones son limpias (llaves nuevas = ID nuevo), pero el `.cfg`
  con la llave privada permite volver atrás.
- **Cambios de radio (preset, región, slot, canal primario) en remoto: del más lejano al más cercano, el nodo
  local al final.** Si cambias primero el local, pierdes a los demás. Probar con un solo nodo antes de la flota.
- Nunca `security.is_managed true` sin haber probado admin remoto en ese nodo (bloqueo total). Nunca
  `security.packet_signature_policy STRICT` mientras quede un nodo 2.7 o STM32WL.
- Nada de `--factory-reset-device` ni full erase sin respaldo `.cfg` del nodo. `--factory-reset` (config) conserva
  las llaves.
- Toda la flota en el build de `flota.yaml:firmware` (nightly fijado). Ningún nodo en 2.8.0 (revocada). El nightly
  se reemplaza a diario: archivar con `$T fw --solo-bajar` antes de cambiar el fijado.
- PSK, WiFi y llaves privadas: solo en `~/.config/meshtastic-fleet/` (600). Nunca en el repo, el chat ni la salida;
  `--info` y `--export-config` imprimen la llave privada: filtrar con `grep -v -i -e private -e psk`.
- Si el clasificador bloquea: detenerse, dar el comando exacto y por qué, y esperar (regla global del usuario).

## Ciclo de aprendizaje (antes de dar la tarea por terminada)

1. ¿Secuencia de 3+ llamadas que se repetirá? → subcomando en `mt.py` (dry-run salvo `--apply`).
2. ¿Un comando falló y encontraste la forma correcta? → `references/hechos.md` § Trampas: `error → forma correcta`.
3. ¿Dato estable nuevo (ID, hardware, decisión)? → `flota.yaml` o `hechos.md` con fecha; borrar lo falso.
4. ¿Release nueva leída? → `firmware.md` (qué cambia para esta flota) y `$T upstream --marcar`.
5. Una línea en `references/bitacora.md`. Versionar en homelab-config (`chore(skill-meshtastic): …`).
