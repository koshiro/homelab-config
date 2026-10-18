# Hechos estables y trampas

## Datos (con fecha)

- Respaldos privados: `~/.config/meshtastic-fleet/backups/<longName>-<id>-<fecha>.{yaml,cfg}` (700/600).
  Secretos: `~/.config/meshtastic-fleet/secretos.yaml` (600; claves `canal_url`, `wifi_ssid`, `wifi_psk`).
- Firmware descargado y verificado: `~/.cache/meshtastic-fw/<versión>/<pio>/`.
- CLI desde fuente: `~/.local/src/meshtastic-python` (master 0a183576, protobufs 2.8.1), venv
  `~/.local/pipx/venvs/meshtastic`. (2026-10-18)
- Repo viejo con experimentos MQTT/bridge: `~/git/meashtastic-router` (2025, no usado por la flota actual).
- CarTracker por USB en la Mac aparece como `/dev/cu.usbmodem101`. (2026-10-18)
- `!793a3263` "Meshtastic 3263", hw UNSET, oído directo (snr 6,25) el 2026-10-18: sin identificar.
- Respaldo CarTracker 2026-10-18: `bluetooth.fixed_pin 123456` (modo RANDOM_PIN), store&forward cliente activo,
  `canned_messages` Hi|Bye|Yes|No|Ok, MQTT apagado.

## Trampas (`error → forma correcta`)

- `timeout 40 meshtastic …` → no existe `timeout` en macOS: usar `meshtastic --timeout 40`.
- `pipx install …` → «pipx needs uv>=0.9.17» → `pipx install --backend pip …`.
- `pip install git+https://github.com/meshtastic/python@sha` → falla el submódulo `http://github.com/meshtastic/protobufs`
  (puerto 80 bloqueado) → clon local con `submodule.protobufs.url` en https (ver cli.md).
- `fd.label == fd.LABEL_REPEATED` → protobuf ≥5 no lo tiene: detectar repetido por el tipo del valor.
- PyPI por WebFetch devuelve un desafío anti-bot → usar `https://pypi.org/pypi/meshtastic/json`.
- `meshtastic --info` / `--export-config` → imprimen `privateKey` y la URL con PSK: filtrar
  `grep -v -i -e private -e psk` antes de mostrar.
- `--set security.packet_signature_policy COMPATIBLE` → hay que dar el nombre completo
  `PACKET_SIGNATURE_POLICY_COMPATIBLE`.
