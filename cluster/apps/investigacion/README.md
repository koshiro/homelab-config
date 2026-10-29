# Plataforma de investigación (namespace `investigacion`)

Repo de la app: `koshiro/investigacion` (privado). Especificación y ADR en su `docs/`. Aquí solo viven los manifiestos;
mergear a `main` despliega (Flux, Kustomization `investigacion`).

| Pieza | Qué es | Red |
|-------|--------|-----|
| `web` | Interfaz (login argon2 + TOTP, investigaciones, visor). **NodePort 30960**, sin Ingress | entra: LAN/tailnet; sale: Postgres |
| `capture` | Atiende `capture_job`, descarga y guarda en `evidencia` (única con escritura) | Postgres + `egress-proxy` (usuario `capture`) |
| `extract` | docling + Tesseract + Presidio/GLiNER, **sin red** (solo Postgres), evidencia en solo lectura | Postgres |
| `llm-gateway` | Único cliente de la API de Claude. **0 réplicas** hasta crear el Secret `anthropic-api` | Postgres + proxy (`llm-gateway`, solo `api.anthropic.com`); entra solo desde `investigacion/gateway: cliente` |
| `lector` | CronJob **suspendido**; lee capturas sin ficha y no aisladas | Postgres + `llm-gateway` |
| `investigacion-pg` | CNPG (PostGIS + pgvector), respaldo barman a Garage | solo clientes `investigacion/db: cliente` |

Roles de la base: un grupo `inv_*` por servicio (permisos mínimos en las migraciones de la app) y un login `usr_*` que
pertenece a él (`managed.roles` de `postgres.yml`; contraseñas en `pg-usr-*.sops.yaml`). Las migraciones las aplica el
initContainer `migrar` de `web` con el rol dueño (`investigacion-pg-app`).

## Puesta en marcha (una vez)

1. Usuario único. El TOTP es el del Secret `web-secreto`; la contraseña la eliges tú (≥ 14 caracteres):

   ```bash
   IMG=$(kubectl -n investigacion get deploy web -o jsonpath='{.spec.template.spec.containers[0].image}')
   kubectl -n investigacion run crear-usuario --rm -it --restart=Never --image="$IMG" \
     --labels=investigacion/db=cliente --overrides='{"spec":{"nodeSelector":{"kubernetes.io/arch":"amd64"},"imagePullSecrets":[{"name":"ghcr-pull"}],"securityContext":{"runAsNonRoot":true,"runAsUser":1000,"seccompProfile":{"type":"RuntimeDefault"}},"containers":[{"name":"crear-usuario","image":"'"$IMG"'","args":["crear-usuario","daniel"],"stdin":true,"tty":true,"env":[{"name":"INVESTIGACION_DATABASE_URL","valueFrom":{"secretKeyRef":{"name":"investigacion-pg-app","key":"uri"}}},{"name":"INVESTIGACION_WEB_TOTP_SECRETO","valueFrom":{"secretKeyRef":{"name":"web-secreto","key":"INVESTIGACION_WEB_TOTP_SECRETO"}}}]}]}}'
   ```

   El `nodeSelector` amd64 es obligatorio: sin él el pod puede caer en pibot (arm64) y queda en `ImagePullBackOff`.
   Imprime el URI `otpauth://…` para la app de autenticación; si no quieres el prompt, define
   `INVESTIGACION_NUEVA_PASSWORD` en `env` del contenedor. Entrar en `http://<IP de un nodo o tailnet>:30960`.
2. API de Claude (cuando Daniel ponga el límite de gasto en la consola de Anthropic): crear
   `anthropic-api.sops.yaml` (clave `ANTHROPIC_API_KEY`), sumarlo a `solo-flux/` y subir `llm-gateway` a 1 réplica por PR.
3. Leer capturas: `kubectl -n investigacion create job lector-$(date +%s) --from=cronjob/lector`.

## Operación

- Capturar: en la web, «Capturar una URL» (solo dominios de `egress-proxy.yml`, lista `capture.txt`).
- Integridad: `/auditoria` valida la cadena de hashes y recalcula el hash de cada captura; por consola:
  `kubectl -n investigacion exec deploy/capture -- investigacion verificar-capturas`.
- Imágenes: `ghcr.io/koshiro/investigacion` (web, capture, llm-gateway, lector) y `…-extract` (pesada, modelos
  horneados). Subir ambas al mismo `sha-…` de `main` del repo de la app.
- El prune de Flux está apagado: lo que se quita de este repo hay que borrarlo a mano (p. ej. el Deployment
  `prototipo` de la fase 0).
