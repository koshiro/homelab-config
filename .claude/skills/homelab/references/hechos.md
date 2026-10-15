# Hechos del homelab (verificados; fecha = cuándo se confirmó)

Solo datos estables. Lo que cambia (pods, NodePorts libres, disco) se consulta con `hl.py`.

## Hosts y acceso
- Master `pibot` (RPi CM4, arm64, 192.168.1.15): ssh `daniel@k3s-node-0` (el nombre `pibot` no resuelve). (2026-10-14)
- Workers VM 102–104 `k3s-node-1/2/3` (192.168.1.131–133, amd64, `cpu: host`): ssh `daniel@192.168.1.13N` o, fuera
  de la LAN, `daniel@k3s-node-N-k3s`. `ssh k3s-node-1` **no resuelve**. (2026-10-14)
- Proxmox `pve` 192.168.1.100; fuera de la LAN `root@pve` (Tailscale). Timeout a 192.168.1.x = no estamos en la red,
  no una caída. (2026-10-13)
- kubectl local apunta a `k3s-node-0:6443`; no hace falta ssh para kubectl. GPU RTX 3070 solo en node-1.
- VM 105 `opencontracts-lab` (192.168.1.140) es un laboratorio temporal: no versionar nada de ella.
- El pod `claude-remote` tiene la misma paridad de acceso (`HOME=/Users/daniel`, repos en `~/git`).

## Cloudflare
- Cuenta `84f8d7966bfc3d39812bebeeeed0cfa4`; zonas `danielriquelme.cl`, `josekast.cl`; túneles `pve` (conectores en
  workers, comodín `*.danielriquelme.cl` → Traefik) y `pibot-webs` (conector en pibot, sitios estáticos → NodePort).
  IDs: `pve` 4268d03e-4f56-46c2-a11e-2105cc6e8c07, `pibot-webs` e09353d9-9758-46ad-9305-1b924e3e4a45;
  `casaos_tunnel` está caído y sin uso. (2026-10-14)
- Token de cuenta `vault_cloudfare_full_api_token` (sic, "cloudfare") en `ansible/vars/vault.yml`;
  `vault_cloudflare_api_token` es solo R2. Es token de cuenta: `/user/tokens/verify` falla, usar endpoints de cuenta.
  `hl.py cf` lo lee en memoria y respalda la config del túnel antes de un PUT. (2026-10-06)
- Web Analytics del plan gratis admite 1 sola regla; para excluir un host se usa Configuration Rule `disable_rum`
  (así está cyano). (2026-10-10)
- Paneles con Cloudflare Access (app «Homelab admin», OTP): grafana, comfyui, swarmui, galeria, chat, *arr, qbittorrent.

## Convenciones
- Series de NodePort: 3089x sitios estáticos en pibot (30890 josekast, 30891 noledigasanadie, 30892 cyano),
  30894 Syncthing de claude-remote. Siempre confirmar con `hl.py ports`.
- Datos: `local-path` = disco de la VM, sin cuota ni respaldo (CronJob `config-backup-<app>` 02:40–02:48);
  valiosos → NFS `nvme/k8s/<app>`; voluminosos reemplazables → `/mnt/homelab-storage/<app>`; pibot → hostPath.
- Postgres compartido CNPG `homelab-postgres-rw.postgresql.svc.cluster.local:5432`.
- Horas: el usuario está en GMT-3; APIs y logs dan UTC: convertir al reportar.

## Trampas (error → forma correcta)
- Guarda del worktree «too complex to verify» / «names git» → un comando simple por llamada; bucles en script de
  `$CLAUDE_JOB_DIR/tmp`; sin `cd … &&` (sus rutas bajo `~/git` se leen como git). (2026-10-14, 128 errores en 29 sesiones)
- `git -C <checkout>` desde un worktree → bloqueado: ExitWorktree `keep` y operar desde el checkout.
- El clasificador puede bloquear `hl.py cf route` aun en dry-run («DNS / Domain / Cert Changes») → detenerse y pedir
  autorización con el comando exacto; no hay forma alternativa. (2026-10-14)
- `sleep N; …` → bloqueado: `hl.py wait`, `kubectl wait --for=…`, o Monitor. (20 veces)
- `sops -d` «Failed to get the data key» → faltaba `SOPS_AGE_KEY_FILE=~/.config/sops/age/keys.txt`: usar `hl.py sops`.
- `ansible-vault view` «requires blocking IO» → `</dev/null` y `| cat` (o `stdin=DEVNULL` en Python).
- `python3 -c 'import yaml'` falla → usar `/opt/homebrew/opt/ansible/libexec/bin/python3` (trae yaml) o evitar yaml.
- Archivo nuevo en `docs/` «ignored by .gitignore» → `git add -f` (gitignore global ignora `docs`).
- `kustomization.yml` vs `.yaml`: varía por app (comfyui usa `.yaml`); listar la carpeta antes de editar.
- zsh: URL con `?` sin comillas → «no matches found»: siempre entre comillas.
- `kubectl top node a b` → no acepta varios nombres: `kubectl top nodes`.
- Contenedor de comfyui no trae curl → `python3 -c urllib…` dentro o pod efímero `curlimages/curl`.
- `kubectl exec` largo con red celular se corta → `nohup … > archivo &` en el pod y leer con llamadas cortas.
- `pkill -f patrón` dentro de `sh -c` se mata a sí mismo → patrón `[p]atrón` o PID.
- `git pull` «Permission denied (publickey)» → reintentar; si persiste, pedir `! git pull` al usuario.
- Tras reiniciar pibot, flannel tarda 1–2 min: 502 transitorio hacia pods de la Pi.
- Pods GPU con «NVML Unknown Error» tras `daemon-reload` en node-1 → `kubectl -n nvidia-device-plugin rollout restart
  ds` y reiniciar los pods con GPU (avisar antes por Plex).
- `systemctl enable zfs-import@homelab-storage` → `%I` cambia `-` por `/` y busca `homelab/storage`: escapar con
  `systemd-escape` → `zfs-import@homelab\x2dstorage.service` (falló en el reinicio de pve del 2026-10-15).
- `ssh root@pve` no responde tras `reboot` aunque `uptime` diga que arrancó hace rato → esperar con `until`; el
  2026-10-15 tardó ~20 min en contestar por SSH (arrancó en ~4).
- CronJob `arr-filtro-archivos` con Jobs `Error` «Connection refused» → Sonarr/Radarr/qBittorrent caídos o
  reiniciando; desde 2026-10-15 el script omite la corrida en vez de fallar.
- ComfyUI web (comfyui.danielriquelme.cl) pide Cloudflare Access → para probar la UI usar el NodePort `http://192.168.1.15:30188`.
- ComfyUI ≥0.38: el panel Media Assets y el escaneo de output/ requieren `--enable-assets` (BD en `/app/user/comfyui.db`). Las fechas del primer escaneo son la hora del escaneo, no la del archivo. Las rutas `x.png [output]` de LoadImage se validan solo contra el historial en memoria: tras reiniciar quedan como faltantes y bloquean Run; se reseleccionan desde Media Assets (el usuario no quiere un nodo propio).
