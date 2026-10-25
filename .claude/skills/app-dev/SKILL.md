---
name: app-dev
description: Diseñar y desarrollar las aplicaciones propias de Daniel para su cluster k3s (cyano, SAC, Job Hunter y las que vengan) sin volver a investigar stacks - arquetipo, stack por defecto con versiones verificadas, estructura del repo, plantillas (pyproject, Dockerfile, CI, CLAUDE.md, ADR), colas en Postgres, LLM local (Ollama) y Claude API, anti-invención y evals, bots de Telegram, correo, PDF/CV, fuentes públicas y scraping limpio. Usar SIEMPRE al empezar, diseñar, elegir stack, escribir un ADR o preparar el despliegue de una app propia, antes de buscar en la web. Los manifiestos, Flux y secretos del cluster van con la skill homelab.
---

# Desarrollo de apps propias

Objetivo: arrancar y construir una app en horas, no en días de investigación. Las decisiones ya están tomadas y
justificadas en `references/`; leer **solo** la que toque. Re-investigar únicamente lo marcado *revisar* o una fila con
fecha de verificación de más de 6 meses (y actualizarla al hacerlo).

## Mapa

| Necesito | Leer |
|----------|------|
| Elegir arquetipo y arrancar | §Arquetipos y §Arranque, abajo |
| Stack por capa, versiones, alternativas descartadas | `references/stack.md` |
| LLM local, embeddings, Claude API (modelos, precio, caché), anti-invención, evals | `references/llm.md` |
| Telegram, correo iCloud, PDF/CV, fuentes públicas, scraping, navegador remoto | `references/integraciones.md` |
| Archivos de arranque | `plantillas/` (pyproject, Dockerfile, ci.yml, CLAUDE.md, adr.md) |
| Cómo se hizo una app concreta y qué se aprendió | `references/casos.md`; Job Hunter: `casos/job-hunter.md` y `casos/job-hunter-codigo.md` |
| Manifiestos, Flux, puertos, secretos, respaldo, Cloudflare | skill **homelab** (receta *app nueva*, `hl.py doc DISENO-APPS`) |

## Arquetipos (elegir uno antes de escribir código)

| | Cuándo | Stack | Despliegue |
|-|--------|-------|-----------|
| **A. Estática local-first** | Todo ocurre en el navegador; sin datos de usuario en servidor | SvelteKit + `adapter-static`, TS, Vitest; núcleo puro en `src/lib/core/` | Sitio en pibot (DISENO-APPS §4.2), `scripts/publicar.sh` con rsync. Modelo: cyano |
| **B. Servicio Python** | API, trabajos en segundo plano, datos relacionales | FastAPI + psycopg 3 + Procrastinate + Pydantic; uv, ruff, pytest | Imagen propia; Deployments `api` y `worker` de la misma imagen; BD en `homelab-postgres` |
| **C. Script o bot pequeño** | Un archivo, casi solo stdlib | `python:3.14-alpine` + `configMapGenerator` | DISENO-APPS §2.4a. Modelo: `cluster/apps/minecraft/whitelist-bot/` |
| **D. Lote** | Corre y termina | B o C con otro comando | CronJob `timeZone: America/Santiago`, `concurrencyPolicy: Forbid` |

Interfaz de un B: panel interno → Jinja + HTMX servido por el mismo FastAPI (sin build de JS). Interfaz rica → SPA
SvelteKit estática aparte que consume la API. Telegram como interfaz principal cuando la interacción es decidir con un
botón desde el teléfono.

## Reglas de diseño (cada una evitó un problema real o un costo)

1. **Postgres es el centro**: datos, cola (Procrastinate, `SKIP LOCKED`), vectores (pgvector), full-text. Sin Redis,
   Celery ni brokers: un componente menos que operar y respaldar.
2. **Una imagen, varios comandos** (`api`, `worker`, `cron`); configuración por variables de entorno (DISENO-APPS §2).
3. **Determinista primero, LLM al final**: API estructurada → JSON-LD → reglas → LLM barato → LLM caro. Cada etapa
   descarta antes de gastar en la siguiente.
4. **Toda salida de LLM se valida con esquema** (Pydantic / structured outputs). Si afirma hechos, un **verificador
   en código** la contrasta con la fuente; nunca otro LLM como única defensa.
5. **Acciones externas con humano en el bucle** (enviar, publicar, postular): aprobación ligada al hash del paquete
   exacto que se mostró, de un solo uso y con vencimiento.
6. **Contenido externo es dato, no instrucción** (páginas, correos, ofertas, PDFs): delimitado en el prompt y sin
   poder cambiar reglas, umbrales ni herramientas.
7. **Nada público sin login fuerte**: panel por tailnet/NodePort o detrás de Cloudflare Access.
8. **Dependencias estables con ≥ 2 semanas publicadas**, versiones fijadas (`uv.lock`, `package-lock.json`) y
   Renovate/Dependabot para subirlas.
9. **Un repo por app** en `~/git/<app>` (privado si hay datos personales); manifiestos en homelab-config. Trabajo por
   fases, un PR por fase y un documento de traspaso si otra sesión la continúa (como `cyano/docs/FASE-5-DESPLIEGUE.md`).
10. **ADR corto** por decisión relevante en `docs/adr/NNNN-*.md` (plantilla en `plantillas/adr.md`).
11. **Fase 1 entrega valor sin IA de pago**; la IA entra cuando hay un set dorado para medirla.

## Arranque de una app nueva

1. Arquetipo + `docs/adr/0001-stack.md` desde `plantillas/adr.md`, citando `references/stack.md`; solo las
   desviaciones necesitan justificación.
2. Repo: `gh repo create koshiro/<app> --private --clone` (confirmar con el usuario: es hacia afuera).
3. Copiar plantillas (B: `pyproject.toml`, `Dockerfile`, `.dockerignore`, `ci.yml` en `.github/workflows/`,
   `CLAUDE.md`) y reemplazar `<app>`. `uv sync && uv run ruff check && uv run pytest` en verde antes del primer commit.
4. Imagen propia (arquetipo B): GHCR privado `ghcr.io/koshiro/<app>`, publicada por el CI de la plantilla. En el
   cluster: `hl.py ghcr secret <ns> …/solo-flux/secret-ghcr-pull.sops.yml` + `imagePullSecrets` (DISENO-APPS §2.4c).
5. Despliegue: skill homelab, receta *app nueva*. Métricas propias → job en
   `cluster/03-monitoring/monitoring/scrape.yml` (el cluster no usa anotaciones de scrape).

## Ciclo de aprendizaje (obligatorio al cerrar una tarea de desarrollo)

1. ¿Elegiste o descartaste una herramienta con evidencia? → fila en `references/stack.md` con fecha y motivo.
2. ¿Patrón nuevo de LLM, integración o fuente? → `references/llm.md` o `integraciones.md`.
3. ¿Terminaste una fase de una app? → lecciones en `references/casos.md` (qué funcionó, qué costó, qué no repetir).
4. ¿Un archivo de arranque cambió en la práctica? → actualizar `plantillas/`.
5. Una línea en `references/bitacora.md`. Mantener este archivo bajo ~100 líneas.

Estudiar un proyecto existente = **clonarlo y leer el código**, no solo el README: `git clone --depth 1` a un
directorio aislado del scratchpad, sin instalar ni ejecutar nada suyo, y anotar archivo, línea, licencia y commit.
