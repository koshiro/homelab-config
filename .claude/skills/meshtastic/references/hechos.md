# Hechos estables y trampas

## Datos (con fecha)

- Respaldos privados: `~/.config/meshtastic-fleet/backups/<longName>-<id>-<fecha>.{yaml,cfg}` (700/600).
  Secretos: `~/.config/meshtastic-fleet/secretos.yaml` (600; claves `canal_privado_nombre`, `canal_privado_psk`, `wifi_ssid`, `wifi_psk`;
  `canal_url` = URL del diseño viejo, solo para volver atrás).
- Firmware descargado y verificado: `~/.cache/meshtastic-fw/<versión>/<pio>/`.
- CLI desde fuente: `~/.local/src/meshtastic-python` (master 0a183576, protobufs 2.8.1), venv
  `~/.local/pipx/venvs/meshtastic`. (2026-10-18)
- Repo viejo con experimentos MQTT/bridge: `~/git/meashtastic-router` (2025, no usado por la flota actual).
- CarTracker por USB en la Mac aparece como `/dev/cu.usbmodem101`. (2026-10-18)
- El cable USB largo de AcevedoRoof a pve es **solo de energía**: en pve no enumera nada (solo el NanoKVM) ni hay
  errores de enumeración en el kernel. (2026-10-18)
- Slots en ANZ con LONG_FAST: 52; malla pública ("LongFast") = slot 20 (~919,875 MHz); el viejo primario `DNTGPS`
  = slot 38. Hash djb2 del nombre del primario % 52. (2026-10-18)
- `!793a3263` "Meshtastic 3263": nodo ajeno oído de viaje; no es de la flota.
- Telegram del homelab: bot de Alertmanager (`cluster/03-monitoring/monitoring/secret-alertmanager-telegram.sops.yaml`).
- Respaldo CarTracker 2026-10-18: `bluetooth.fixed_pin 123456` (modo RANDOM_PIN), store&forward cliente activo,
  `canned_messages` Hi|Bye|Yes|No|Ok, MQTT apagado.

## Trampas (`error → forma correcta`)

- `timeout 40 meshtastic …` → no existe `timeout` en macOS: usar `meshtastic --timeout 40`.
- `pipx install …` → «pipx needs uv>=0.9.17» → `pipx install --backend pip …`.
- `pip install git+https://github.com/meshtastic/python@sha` → falla el submódulo `http://github.com/meshtastic/protobufs`
  (puerto 80 bloqueado) → clon local con `submodule.protobufs.url` en https (ver cli.md).
- `fd.label == fd.LABEL_REPEATED` → protobuf ≥5 no lo tiene: detectar repetido por el tipo del valor.
- PyPI por WebFetch devuelve un desafío anti-bot → usar `https://pypi.org/pypi/meshtastic/json`.
- `urllib` contra nightly.meshtastic.org / release.meshtastic.org → 403 (Cloudflare bloquea el User-Agent por
  defecto) → `User-Agent: curl/8 …` (función `pedir` de mt.py).
- `--seturl` escribe canales **y** la config lora de la URL, y no borra canales sobrantes → mt.py arma la URL con la
  lora deseada y borra sobrantes con `--ch-index N --ch-del` de mayor a menor.
- `meshtastic --info` / `--export-config` → imprimen `privateKey` y la URL con PSK: filtrar
  `grep -v -i -e private -e psk` antes de mostrar.
- `--set security.packet_signature_policy COMPATIBLE` → hay que dar el nombre completo
  `PACKET_SIGNATURE_POLICY_COMPATIBLE`.
