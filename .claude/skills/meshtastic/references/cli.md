# CLI `meshtastic` (Python)

## Instalación (por qué no PyPI)

PyPI va en 2.7.11 (protobufs 2.7.26): no conoce `security.packet_signature_policy`, `channel.use_aead`, MEDIUM_TURBO,
TINY_*, `tak`, `mesh_beacon`. Master trae protobufs 2.8.1 (commit 77c29654, 2026-10-02). Instalado desde fuente:

```bash
git -C ~/.local/src/meshtastic-python fetch -q && git -C ~/.local/src/meshtastic-python checkout -q <sha>
git -C ~/.local/src/meshtastic-python submodule update --init --recursive
pipx install --backend pip --force ~/.local/src/meshtastic-python
```

- `.gitmodules` apunta a `http://github.com/...` (puerto 80 bloqueado aquí) → ya está `submodule.protobufs.url`
  en https en la config local del clon.
- `pipx` falla con uv 0.4.30 (exige ≥0.9.17) → `--backend pip`.
- `meshtastic --version` sigue diciendo 2.7.11 aunque sea master: verificar con `mt.py` o
  `python -c "from meshtastic.protobuf import config_pb2 as c; print(c.Config.SecurityConfig.DESCRIPTOR.fields_by_name.keys())"`.
- Cuando PyPI publique una versión con protobufs ≥2.8.1: volver a `pipx install meshtastic` y anotarlo aquí.
- `esptool` 5.6.0 instalado con pipx (para `device-install.sh`); `jq` viene en macOS.

## Conexión

| Medio | Flag | Nota |
|-------|------|------|
| USB serial | `--port /dev/cu.usbmodemXXXX` | ESP32-S3 y nRF52 aparecen como usbmodem; un solo cliente a la vez |
| TCP (WiFi/Ethernet) | `--host <ip>` | puerto 4403; sin autenticación: solo LAN/tailnet. Con MeshMonitor usar su nodo virtual (4404) |
| BLE | `--ble <nombre o MAC>` | lento; en ESP32 BLE se apaga si WiFi está activo |
| Remoto por radio | `--dest '!xxxxxxxx'` + una de las anteriores | PKC: la llave pública del nodo conectado debe estar en `security.admin_key` del destino |

`--timeout 60` en remoto (por defecto 300 s espera ACK). `--ack` para esperar confirmación de mensajes.

## Lectura

```bash
meshtastic --info                      # todo; imprime privateKey y canal URL con PSK → filtrar antes de mostrar
meshtastic --nodes                     # tabla de nodos (favoritos incluidos)
meshtastic --get lora --get security   # secciones; remoto: --dest !id --get lora (tarda, pide config por radio)
meshtastic --device-metadata           # firmware, hw, capacidades
meshtastic --export-config f.yaml      # .yaml legible; f.cfg = DeviceProfile binario (lo que usan las apps)
meshtastic --qr-all / --qr             # URL de canales
```

## Escritura

```bash
meshtastic --set lora.modem_preset LONG_FAST --set lora.hop_limit 3   # varias --set = una transacción
meshtastic --set security.admin_key base64:<pubkey>   # repetido: AGREGA (máx. 3)
meshtastic --set security.admin_key 0                 # repetido: VACÍA la lista (¡no hacerlo en remoto!)
meshtastic --set device.role TRACKER                  # enums por nombre; un nombre inválido lista las opciones
meshtastic --set security.packet_signature_policy PACKET_SIGNATURE_POLICY_COMPATIBLE   # nombre completo del enum
meshtastic --set-owner 'Nombre' --set-owner-short 'XX' # long name ≤24 bytes en 2.8
meshtastic --seturl '<url>'          # reemplaza canales Y la config lora que trae la URL
meshtastic --ch-index 1 --ch-set name x --ch-set psk random   # canal secundario
meshtastic --ch-set use_aead true --ch-index 0        # solo con toda la flota en 2.8.1
meshtastic --configure f.yaml        # restaura .yaml (también acepta .cfg)
meshtastic --setlat -33.4 --setlon -70.6 --setalt 600   # posición fija (activa position.fixed_position)
meshtastic --set-favorite-node '!id' / --remove-node '!id' / --reset-nodedb
meshtastic --add-contact '<url de contacto>'   # intercambio de llaves PKC sin esperar NodeInfo (2.7.10+)
```

## Reinicios y reset

| Flag | Efecto |
|------|--------|
| `--reboot` | reinicia (local o `--dest`) |
| `--factory-reset` | config por defecto, **conserva llaves PKI** y bonds BLE |
| `--factory-reset-device` | todo por defecto, **borra llaves** → número de nodo nuevo |
| `--enter-dfu` | nRF52 a modo UF2 (aparece unidad USB) |
| `--ota-update <firmware-…bin>` | ESP32 ≥2.7.18 por WiFi/TCP, sin borrar config |
| `--reboot-ota` | solo ESP32 <2.7.18 (obsoleto para esta flota) |

## API Python (para scripts; `mt.py` la usa)

`SerialInterface(devPath=…)` / `TCPInterface(hostname=…)` → `iface.localNode.localConfig|moduleConfig|channels`,
`iface.nodes`, `iface.metadata`, `iface.myInfo.pio_env`. Remoto: `node = iface.getNode('!id', requestChannels=False)`
y `node.requestConfig(LocalConfig.DESCRIPTOR.fields_by_name['lora'])`. `meshtastic.__main__.export_config(iface)`
y `export_profile(iface)` devuelven el respaldo. En protobuf ≥5 `FieldDescriptor` ya no tiene `.label`.
