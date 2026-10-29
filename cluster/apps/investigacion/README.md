# Plataforma de investigación (namespace `investigacion`)

Repo de la app: `koshiro/investigacion` (privado). Especificación y ADR en su `docs/`. Aquí solo viven los manifiestos;
mergear a `main` despliega (Flux, Kustomization `investigacion`).

| Pieza | Qué es | Red |
|-------|--------|-----|
| `web` | Interfaz (login argon2 + TOTP, investigaciones, visor). **NodePort 30960**, sin Ingress | entra: LAN/tailnet; sale: Postgres |
| `capture` | Atiende `capture_job`, descarga y guarda en `evidencia` (única con escritura) | Postgres + `egress-proxy` (usuario `capture`) |
| `extract` | docling + Tesseract + Presidio/GLiNER, **sin red** (solo Postgres), evidencia en solo lectura | Postgres |
| `llm-gateway` | Único cliente de la API de Claude (clave y límite de gasto confirmados por Daniel el 2026-10-29) | Postgres + proxy (`llm-gateway`, solo `api.anthropic.com`); entra solo desde `investigacion/gateway: cliente` |
| `lector` | CronJob **suspendido**; lee capturas sin ficha y no aisladas (en la fase 2 es un paso del worker) | Postgres + `llm-gateway` |
| `worker` | Flujos DBOS de los agentes (esquema `dbos_worker`): planes que Daniel pide y aprueba, descubrimiento de canales, inventario, lector, hallazgos, borradores | Postgres + `llm-gateway` + `searxng` |
| `searxng` | Búsqueda web del investigador (solo JSON; el worker usa título y URL) | entra solo desde `investigacion/searxng: cliente`; sale por el proxy (usuario `searxng`, `searxng.txt`) |
| `investigacion-pg` | CNPG (PostGIS + pgvector), respaldo barman a Garage | solo clientes `investigacion/db: cliente` |

Roles de la base: un grupo `inv_*` por servicio (permisos mínimos en las migraciones de la app) y un login `usr_*` que
pertenece a él (`managed.roles` de `postgres.yml`; contraseñas en `pg-usr-*.sops.yaml`). Las migraciones las aplica el
initContainer `migrar` de `web` con el rol dueño (`investigacion-pg-app`).

## Puesta en marcha (una vez)

1. Usuario único. El TOTP es el del Secret `web-secreto`; la contraseña la eliges tú (≥ 14 caracteres):

   ```bash
   IMG=$(kubectl -n investigacion get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}')
   kubectl -n investigacion run crear-usuario --rm -it --restart=Never --image="$IMG" \
     --labels=investigacion/db=cliente --overrides='{"spec":{"imagePullSecrets":[{"name":"ghcr-pull"}],"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"crear-usuario","image":"'"$IMG"'","args":["crear-usuario","daniel"],"stdin":true,"tty":true,"env":[{"name":"INVESTIGACION_DATABASE_URL","valueFrom":{"secretKeyRef":{"name":"investigacion-pg-app","key":"uri"}}},{"name":"INVESTIGACION_WEB_TOTP_SECRETO","valueFrom":{"secretKeyRef":{"name":"web-secreto","key":"INVESTIGACION_WEB_TOTP_SECRETO"}}}]}]}}'
   ```

   Imprime el URI `otpauth://…` para la app de autenticación. Entrar en `http://<IP de un nodo o tailnet>:30960`.
2. API de Claude (cuando Daniel ponga el límite de gasto en la consola de Anthropic): crear
   `anthropic-api.sops.yaml` (clave `ANTHROPIC_API_KEY`), sumarlo a `solo-flux/` y subir `llm-gateway` a 1 réplica por PR.
3. Leer capturas: `kubectl -n investigacion create job lector-$(date +%s) --from=cronjob/lector`.

## Operación

### Fase 2: agentes

1. En la web, en la investigación, «Proponer plan». El worker lo encola (flujo `plan-<id>`) y el investigador lo
   propone; nada se ejecuta hasta aprobarlo en **Aprobaciones** (TOTP nuevo en cada decisión).
2. Canales de transparencia, hallazgos con citas en `revisar`, capturas aisladas y borradores también se aprueban ahí.
3. Datos del solicitante para los borradores (opcional; si falta, quedan marcadores): Secret `solicitante` con
   `INVESTIGACION_SOLICITANTE_NOMBRE` e `INVESTIGACION_SOLICITANTE_CORREO`, cifrado con SOPS y sumado a `solo-flux/`.
4. Estado de un flujo: `kubectl -n investigacion logs deploy/worker`; tareas y costo en la página de la investigación.
5. SearXNG: al arrancar intenta bajar las listas de ClearURLs directo (sin proxy) y la NetworkPolicy lo corta; el aviso
   en el log es esperado. Motores: duckduckgo y brave (startpage y mojeek vienen inactivos por captcha).

- Capturar: en la web, «Capturar una URL» (solo dominios de `egress-proxy.yml`, lista `capture.txt`).
- Integridad: `/auditoria` valida la cadena de hashes y recalcula el hash de cada captura; por consola:
  `kubectl -n investigacion exec deploy/capture -- investigacion verificar-capturas`.
- Imágenes: `ghcr.io/koshiro/investigacion` (web, capture, llm-gateway, lector) y `…-extract` (pesada, modelos
  horneados). Subir ambas al mismo `sha-…` de `main` del repo de la app.
- El prune de Flux está apagado: lo que se quita de este repo hay que borrarlo a mano (p. ej. el Deployment
  `prototipo` de la fase 0).
