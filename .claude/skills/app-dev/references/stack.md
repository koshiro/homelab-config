# Stack por capa

Versiones verificadas en PyPI/npm el **2026-10-25**. «Elegido» es el valor por defecto: usarlo sin discutir salvo que
la app lo impida (y entonces ADR). «Descartado» dice por qué, para no volver a evaluarlo.

## Python (arquetipos B, C, D)

| Capa | Elegido (versión) | Por qué | Descartado / alternativa |
|------|-------------------|---------|--------------------------|
| Lenguaje | Python 3.14 (3.13 si una dependencia no tiene wheel) | Imágenes oficiales `python:3.14-slim`/`-alpine`; ya usado en el cluster | — |
| Proyecto y entorno | **uv** 0.13 (`uv init --package`, `uv.lock`, `uv run`) | Un binario: Python, venv, lock y scripts; build de imagen rápido | pip-tools, Poetry, PDM. Nota: Astral pasó a OpenAI (jul-2026); las herramientas siguen MIT/Apache |
| Lint y formato | **ruff** 0.17 | Uno solo para lint + formato. La 0.16 subió las reglas por defecto de 59 a 413: fijar versión y `select` explícito | flake8, black, isort |
| Tipos | **ty** 0.0.x en CI como aviso (no bloquea); pyright si hace falta bloquear | ty es rápido pero sigue en beta | mypy (lento) |
| Tests | **pytest** 9.1 (+ `pytest-asyncio`) | Estándar; los evals de LLM también se escriben como tests | unittest |
| Web/API | **FastAPI** 0.162 + **uvicorn** 0.54 | Pydantic v2, OpenAPI, ecosistema y lo que más conocen los modelos | Litestar 2.25 (más rápido con msgspec, menos ecosistema); granian 2.8 como servidor si el rendimiento importa |
| Config | `pydantic-settings` | Variables de entorno tipadas, falla al arrancar si falta algo | dotenv suelto |
| Postgres | **psycopg** 3.3 (async, pool) + SQL explícito | Sin capa mágica; SQL revisable; `COPY` y `LISTEN` nativos | SQLAlchemy 2.1 Core solo si hay consultas dinámicas complejas; SQLModel (0.0.x tras años) |
| Migraciones | SQL plano numerado `migrations/NNNN_*.sql`, aplicado al arrancar con `pg_advisory_lock` (≈40 líneas) | Idempotente, sobrevive cortes de luz (DISENO-APPS §2.16), sin dependencia | Alembic 1.20 si se usa SQLAlchemy ORM |
| Cola y periódicas | **Procrastinate** 3.10 (`periodic` con cron, reintentos, locks, cola por nombre) | Postgres-only, async, trabajos en la misma transacción que sus datos | PgQueuer 1.6 (más throughput, LISTEN/NOTIFY; elegir si >1k trabajos/s); DBOS 3.3 (workflows durables con pasos reanudables: solo si hace falta); Celery/RQ/arq/Dramatiq (exigen Redis); Hatchet/Temporal (servidor aparte) |
| Programación | Periódicas dentro del worker (Procrastinate `periodic`) | Un Deployment, historial y reintentos en la BD | CronJob de k8s cuando necesita otros recursos o aislamiento (arquetipo D) |
| HTTP saliente | **httpx** 0.28 (async, HTTP/2, timeouts) + reintentos con backoff propio | Estable y maduro | requests (sin async), aiohttp |
| RSS | **feedparser** 6.0.14 | Tolera feeds rotos | — |
| HTML | **selectolax** 1.0 (parser rápido) + JSON-LD con `json.loads` sobre `script[type="application/ld+json"]`; **trafilatura** 2.3 para texto principal | Barato y determinista antes de cualquier LLM | BeautifulSoup (lento); extruct (sin release desde 2024) |
| HTML/PDF/DOCX → Markdown | **markitdown** 0.1.9 (simple); **docling** 2.142 (PDF con layout, tablas, OCR) | Entrada limpia para LLM | — |
| Dedup difusa | **rapidfuzz** 3.14 (títulos); **datasketch** 2.0 (MinHash) o similitud de embeddings | Determinista y barato | — |
| Logs | **structlog** 26.1 en JSON a stdout | DISENO-APPS §2.9; parseable en Grafana | logging plano |
| Métricas | **prometheus-client** 0.26 en `/metrics` + job en `cluster/03-monitoring/monitoring/scrape.yml` | VictoriaMetrics raspa por job explícito, no por anotaciones | OpenTelemetry metrics (más piezas) |
| Telegram | **aiogram** 3.31 | Async nativo (convive con FastAPI), routers, FSM, `CallbackData` tipada | python-telegram-bot 22.8 (bien, pero su loop propio choca con FastAPI) |
| Navegador | **Playwright** 1.64 (Python) | Formularios, liveness, render HTML→PDF | Selenium |
| PDF | **Typst** 0.15 vía paquete `typst` (compila en proceso, sin binario) | Plantillas `.typ` + datos JSON; PDF con texto real | WeasyPrint 70 (HTML/CSS); RenderCV 2.8 para CVs en YAML (ver integraciones) |
| SDK Claude | **anthropic** 2.3 | Oficial; `messages.parse()` con Pydantic, batches, caché | Shims OpenAI-compatibles |
| SDK Ollama | **ollama** 0.6 (`format=<JSON schema>`) | Salida estructurada nativa | Endpoint OpenAI-compatible (pierde `think`, `keep_alive`) |
| Agentes multi-proveedor | **pydantic-ai** 2.61 solo si hay herramientas + varios proveedores | Tipado, DI, trazas | instructor 1.17 para extracción validada con reintento si no se quiere el SDK nativo; LangChain/LangGraph (capas de más) |
| Evals | pytest + set dorado propio; **promptfoo** (CLI npm) para matrices prompt × modelo | Sin servidor | deepeval 4.3 (métricas G-Eval, más pesado) |
| Trazas de LLM | Tabla `llm_calls` (modelo, tokens, costo, latencia, hash de prompt) + métrica | Suficiente para una persona | Langfuse (MIT, pero ClickHouse + Redis + S3); Phoenix (ELv2, un proceso) solo si hace falta inspeccionar trazas |

## Web (arquetipo A y UIs ricas)

| Capa | Elegido (versión) | Notas |
|------|-------------------|-------|
| Framework | **SvelteKit** 3.1 + **Svelte** 5.57 (runes), `adapter-static` | Kit 3 estable desde oct-2026 (exige Vite 8, Node 22+, quita `$app/stores`; `npx sv migrate sveltekit-3`). Cyano sigue en 2.x hasta evaluarlo. *Remote functions*: experimentales, no usar |
| Build | **Vite** 8.3, Node 24, npm con `package-lock.json` | — |
| Lenguaje | **TypeScript** 7.0 (compilador nativo en Go) | Cyano en 6.0; subir junto con Kit 3 |
| Tests | **Vitest** 5 (núcleo), **Playwright** 1.64 (e2e) | Núcleo puro testeado sin DOM |
| Componentes accesibles | **Bits UI** 2.20 (headless) o propios | Listbox/combobox accesibles; cyano prohíbe `<select>` nativo |
| Estilos | Tokens propios OKLCH en 3 niveles (doctrina de cyano) | Tailwind 4.3 aceptable si no hay sistema de diseño |
| Panel interno sin build | **HTMX** 2.0.x + Jinja | HTMX 4 está en `next`: no usar hasta estable |
| PWA | Service worker de SvelteKit + `manifest.webmanifest` | Ver nginx de `cluster/apps/cyano/configmap-nginx.yml` (no-cache al SW, inmutable a `/_app/immutable/`) |

## Datos

| Necesidad | Elegido | Verificado |
|-----------|---------|------------|
| Relacional | Base propia en `homelab-postgres` (CNPG 1.27, Postgres 17.11, 3 instancias) | DISENO-APPS §4.5 |
| Vectores | **pgvector 0.8.6** ya disponible en la imagen `ghcr.io/cloudnative-pg/postgresql:17.11`; declarar con `spec.extensions: [{name: vector, ensure: present}]` en el CRD `Database` | 2026-10-25 (`pg_available_extensions`, `kubectl explain database.spec.extensions`) |
| Texto | full-text `spanish`/`english`, `pg_trgm` 1.6, `unaccent` 1.1 disponibles | 2026-10-25 |
| Un solo usuario y sin concurrencia | SQLite en PVC `local-path` | DISENO-APPS §3 |
| Archivos generados | R2 (`hl.py r2`) o Garage en pve (S3 local, ya usado por CNPG) | — |

## Imagen y CI (arquetipo B)

| Tema | Elegido | Por qué / descartado |
|------|---------|----------------------|
| Dockerfile | Multi-stage con uv (`plantillas/Dockerfile`), `python:3.14-slim`, UID 1000, sin root, compatible con `readOnlyRootFilesystem` | DISENO-APPS §2.7 |
| Registry | **GHCR privado** (`ghcr.io/koshiro/<app>`): almacenamiento y transferencia de imágenes gratis según la doc de facturación de GitHub; pull con token `read:packages` en un Secret `dockerconfigjson` cifrado con SOPS | Zot (binario único, CNCF) si se quiere autoalojar; Harbor demasiado pesado. **Decisión pendiente del usuario** |
| Build | GitHub Actions + `docker/build-push-action` con caché `type=gha`; tags `sha-<7>` y semver; amd64 (agregar arm64 solo si puede correr en pibot) | — |
| Despliegue de versiones | Fase inicial: PR en homelab-config que cambia el tag. Después: Flux image automation (ImageRepository + ImagePolicy por semver + ImageUpdateAutomation) | Nunca `latest` |
| Bucle de desarrollo | Local con `uv run` contra Postgres local (Docker) o `kubectl port-forward svc/homelab-postgres-rw`; probar en el cluster con `flux suspend` | Tilt, Skaffold, DevSpace, mirrord: sobra a esta escala |
