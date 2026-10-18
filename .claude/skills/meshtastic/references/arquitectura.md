# Arquitectura de la flota

Decisiones con fecha y porqué. Cambiar una decisión = editar aquí y en `flota.yaml`.

## Uso

Malla privada para seguir 3 trackers (auto + 2 mascotas), con base fija en el techo, nodo personal (Dnto_L1, que
además administra a los demás), nodo del laptop y algunos extras.

## Radio (2026-10-18)

- Región `ANZ` (915–928 MHz, 30 dBm): la que corresponde a Chile.
- Preset `LONG_FAST`. Se evaluó LONG_TURBO: +25 % de velocidad (1,34 vs 1,07 kbps, CR 4/8) a cambio de −3 dB
  (~30 % menos alcance). Para trackers de mascotas pesa más el alcance. Volver a evaluar solo si la malla se satura.
- `channel_num 0` → la frecuencia sale del hash del nombre del canal primario (`DNTGPS`). La flota **no** está en la
  frecuencia de la malla pública LongFast de Chile.
- Hop limit 3. Firma `COMPATIBLE` hasta que toda la flota esté en 2.8.1; luego evaluar `BALANCED`.

## Canales

| Índice | Nombre | PSK | Para qué |
|--------|--------|-----|----------|
| 0 primario | DNTGPS | 32 B privada | posiciones precisas (`position_precision 32`) y mensajes de la flota |
| 2 secundario | default | `AQ==` (pública) | heredado. Como el primario no es LongFast, no conecta con la malla pública |

URL completa (con PSK) solo en `~/.config/meshtastic-fleet/secretos.yaml:canal_url`. **Pendiente decidir**: quitar el
canal `default` o dejarlo.

## Roles

| Nodo | Rol | Por qué |
|------|-----|---------|
| CarTracker, CatTracker, 2.º tracker | TRACKER | prioriza su posición; smart broadcast (10 m / 15 s, máx. 1 h) |
| AcevedoRoof | CLIENT_BASE | base personal: siempre retransmite lo de sus **favoritos** (marcar toda la flota como favorita en él) y el resto como CLIENT |
| Dnto_L1, laptop | CLIENT | móviles; fuera de casa deben retransmitir |

No usar ROUTER/REPEATER: la documentación lo desaconseja salvo en sitios estratégicos y aquí CLIENT_BASE cubre el caso.

## Administración

- `security.admin_key` en todos = llaves públicas de `admins` en `flota.yaml` (Dnto_L1, AcevedoRoof y el laptop
  cuando se identifique; máximo 3). Así cualquiera de los tres administra al resto por PKC (`--dest`).
- Claude administra desde la Mac con `mt.py` / `meshtastic`: por USB, o por TCP al techo (vía MeshMonitor) + `--dest`
  para los demás. Sin MCP por ahora: el CLI por Bash cubre todo y la skill guarda el conocimiento. Un MCP propio
  tiene sentido solo si se quiere administrar desde claude.ai sin terminal (lo natural sería encima de la API REST
  de MeshMonitor).
- `is_managed` apagado en todos (requiere admin remoto probado; si falla, bloquea la configuración desde apps).
- Respaldos con llave privada en `~/.config/meshtastic-fleet/backups/` (700/600). Pendiente: copia cifrada con SOPS.

## Homelab (decisión 2026-10-18, por implementar)

```
 [trackers, Dnto_L1, laptop] ~~LoRa~~ [AcevedoRoof XIAO S3] --WiFi--> LAN --TCP 4403--> MeshMonitor (k3s)
                                                                                        ├─ web UI (Cloudflare Access)
                                                                                        ├─ nodo virtual 4404 (LAN/tailnet) ← CLI, apps
                                                                                        └─ API REST /api/v1 (token)
```

- AcevedoRoof por WiFi a la LAN con IP fija (reserva DHCP). En ESP32, WiFi activo apaga BLE.
- MeshMonitor (`ghcr.io/yeraze/meshmonitor`, chart Helm oficial `https://meshmonitor.org/charts`, 4.17.x) como única
  conexión TCP al nodo: el firmware ESP32 atiende un cliente API a la vez y MeshMonitor multiplexa con su nodo
  virtual. "Allow admin commands" del nodo virtual: activarlo solo si el puerto 4404 no sale de la LAN/tailnet.
- Seguir el contrato de apps del homelab (skill **homelab**, receta *app nueva*): Flux, NodePort, PVC, respaldo.
- MQTT: no hace falta al inicio (MeshMonitor lee por TCP). Si se quiere el broker embebido de MeshMonitor (1883, sin
  TLS) o mapas públicos, decidirlo aparte; `map_reporting` siempre apagado (malla privada).
- 2.8 cambia números de nodo: MeshMonitor detecta el par viejo/nuevo y permite fusionar historial.
