# Job Hunter: investigación (2026-10-25)

Insumo para implementar el documento *Job Hunter — sistema de búsqueda y postulación remota* (25-oct-2026). Revisa
qué existe en open source, verifica en vivo las fuentes y propone ajustes al diseño. Lo genérico (stack, LLM,
integraciones) quedó en las otras referencias de la skill; aquí solo lo propio de Job Hunter.

## Conclusiones

1. **Ningún proyecto open source cumple los invariantes** (Postgres + Telegram + cluster + aprobación por paquete +
   verificador anti-invención). Conviene construirlo, copiando ideas y código MIT de tres proyectos (tabla abajo).
   No hace falta inventar el catálogo de fuentes ni el modelo de aprobación.
2. **El diseño va bien encaminado**: dos puntos humanos, cero invención, fuentes limpias, Postgres al centro y
   Procrastinate coinciden con lo que hacen los mejores proyectos de 2026. Los ajustes son de precisión, no de rumbo.
3. **Cambio de criterio más importante: «todo local primero» ya no conviene para la extracción.** Claude Haiku 5.5
   cuesta USD 0,10 / 0,50 por MTok: extraer y explicar ~100 ofertas diarias cuesta **~USD 1–2 al mes** (la mitad con
   Batches), sin competir con ComfyUI por los 8 GB de VRAM y con mejor JSON. Ollama queda para embeddings (bge-m3) y
   como respaldo. Las ofertas son públicas y el CV es un documento que igual se envía; las Notas privadas no se
   importan nunca.
4. **Puntaje en dos pasos**: primero compuertas (excluir / preguntar / descartar / revisar), después el número. Y un
   **chequeo de vigencia** de la oferta antes de gastar tokens o notificar.
5. **Única decisión que bloquea el despliegue**: el registry de imágenes (es la primera app del cluster con imagen
   propia). Recomendado: GHCR privado.

## Estado del arte open source (oct-2026)

| Proyecto | Licencia · actividad | Qué hace | Qué copiar | Por qué no adoptarlo tal cual |
|----------|----------------------|----------|------------|-------------------------------|
| [career-ops](https://github.com/career-ops-hq/career-ops) | MIT · ~77k★, muy activo (oct-2026) | Agente dentro de Claude Code/Codex: escaneo sin tokens de 55+ fuentes (APIs públicas de ATS, RSS), evaluación A–H con puntaje 1–5, CV y carta en PDF (HTML + Playwright), tracker. Nunca envía | Catálogo de *providers* y `portals.yml` (filtros `word:`/`stem:`/`a + b`, `block_hard`, «no penalizar dato faltante»); chequeo de vigencia antes del LLM; **bloqueo del PDF si una cifra no está en el CV**; tier de legitimidad (oferta fantasma, reposteo, antigüedad); confianza de la evidencia separada del puntaje; contenido externo como dato | Node + archivos Markdown como fuente de verdad, corre dentro de un CLI interactivo; sin Telegram, Postgres ni servicio 24/7 |
| [job-application-agent](https://github.com/vaibhavarora14/job-application-agent) (JobAppAgent) | MIT · 164★, muy activo (release 3.8.4, 23-oct-2026) | Skill + CLI: descubre, califica, llena formularios de Greenhouse/Ashby/Lever, registra solo envíos confirmados | **Compuertas antes del puntaje** (`exclude`/`ask`/`skip`/`review`); puntaje determinista sobre requisitos `met/partial/missing/unclear` con evidencia; **token de aprobación ligado al paquete exacto, de un uso, 24 h**; «llenado ≠ postulado»; duplicados por URL/ID/requisición + enfriamiento de 15 días por empresa; cola de atención (SSO, MFA, CAPTCHA, preguntas legales o demográficas); topes anti-bucle | Node; no ajusta el CV (sube uno canónico); **telemetría y envío de contacto activados por defecto** |
| [ApplyPilot](https://github.com/Pickle-Pixel/ApplyPilot) | AGPL-3.0 · ~1.8k★, dormido desde mar-2026 | Postulación 100 % autónoma («1.000 en 2 días»), CapSolver, JobSpy sobre LinkedIn/Indeed | Extracción en cascada **JSON-LD → selectores CSS → LLM**; `/no_think` para Qwen 3 en Ollama; `--dry-run` que llena sin enviar | Contraejemplo: viola los invariantes 1 y 4 (envía solo, resuelve CAPTCHAs, raspa LinkedIn); sin tests |
| [JobOps](https://github.com/DaKheera47/job-ops) | AGPL + Commons Clause · ~2.6k★ | Next.js autoalojado: búsqueda en 10+ portales, puntaje 0–100, CV con Reactive Resume, seguimiento de correos. No postula | Ideas de UX del pipeline (buscar → puntuar → ajustar → exportar → seguir) | Licencia restrictiva; raspa LinkedIn/Indeed/Glassdoor |
| [JobSpy](https://pypi.org/project/python-jobspy/) | MIT · `python-jobspy` 1.4.1 (23-oct-2026) | Librería que raspa LinkedIn, Indeed, Glassdoor, Google, ZipRecruiter | — | Raspa portales cuyos términos lo prohíben (invariante 4) |
| [Resume-Matcher](https://github.com/srbhr/Resume-Matcher) | Apache-2.0 · ~25k★ | CV maestro → CV ajustado por oferta, con Ollama | Flujo «CV maestro → variante por oferta» | Sin verificador de hechos ni fuentes de ofertas |
| [RenderCV](https://github.com/rendercv/rendercv) | MIT · 2.8 | CV en YAML → Typst → PDF | Render: el generador puede emitir su YAML y heredar temas ATS de una columna | — (usar como librería) |
| JobSync | MIT · sin actividad desde ene-2025 | Tracker Next.js con IA | — | Abandonado |

**Atajo opcional (fase 0, 1 semana, sin código):** correr career-ops en el pod `claude-remote` con el CV maestro y
`portals.yml` ajustado a LATAM/remoto. Sirve para armar el **set dorado** de la fase 2 (100 ofertas etiquetadas) y
descubrir qué fuentes rinden, antes de escribir adaptadores. Gasta tokens de la suscripción de Claude Code, no de API.

## Fuentes verificadas en vivo (2026-10-25)

| Fuente | Endpoint probado | Resultado | Condiciones (del propio feed) | Nota |
|--------|------------------|-----------|-------------------------------|------|
| Get on Board | `GET https://www.getonbrd.com/api/v0/search/jobs?query=devops&per_page=…` y `/api/v0/categories/programming/jobs` | 200 JSON (`data`, `meta`) | API pública sin clave; la privada es para empresas | Para traer la empresa: `expand[]=company` (200); `expand=["company"]` da 400. Doc: `api-doc.getonbrd.com` |
| Himalayas | `/jobs/api?limit=` y `/jobs/api/search?q=&country=CL` | 200 | Paginación por **cursor** (`nextCursor`) desde 21-ago-2026; `offset` deprecado | Trae `locationRestrictions`, `timezoneRestrictions`, `minSalary/maxSalary`, `seniority`, `applicationLink`: la mejor para el filtro de elegibilidad |
| Remotive | `/api/remote-jobs?category=devops` | 200 | Máx. 4 llamadas/día; ofertas con 24 h de retraso; enlazar y citar a Remotive; no redistribuir | Uso personal OK |
| Remote OK | `/api` | 200, lista de 100 | Atribución y enlace de vuelta | El primer elemento es el aviso legal: saltarlo |
| Jobicy | `/api/v2/remote-jobs?count=&tag=` | 200 | Citar a Jobicy; postular en la URL original | Cursor (`nextCursor`, `hasMore`) |
| We Work Remotely | `/categories/remote-devops-sysadmin-jobs.rss` (uno por categoría) | 200 RSS | — | — |
| Arbeitnow | `/api/job-board-api` | 200, 300 por página | — | Mayoría presencial en Europa: filtrar `remote: true` |
| Greenhouse | `boards-api.greenhouse.io/v1/boards/<slug>/jobs?content=true` | 200 (gitlab: 239) | Sin clave | Preguntas del formulario: `/jobs/<id>?questions=true` (200, 13 preguntas en la prueba) |
| Ashby | `api.ashbyhq.com/posting-api/job-board/<slug>?includeCompensation=true` | 200 | Sin clave | Trae compensación con el parámetro |
| Lever | `api.lever.co/v0/postings/<slug>?mode=json` | 200 (spotify) | 1 req/s | Un slug inexistente da 404: tratarlo como «empresa sin tablero», no como error de fuente |
| Workable | `GET apply.workable.com/api/v1/widget/accounts/<slug>` o `POST …/api/v3/accounts/<slug>/jobs` con filtros en JSON | 200 (hotjar) | 1 cada 3 s | El v3 solo acepta POST |
| **HN «Who is hiring?»** | `hn.algolia.com/api/v1/search_by_date?tags=story,author_whoishiring` | 200 | — | **Agregar**: hilo mensual con mucho remoto; los comentarios se parsean con LLM barato |
| Empleos Públicos | `www.empleospublicos.cl` | 403 desde el datacenter | — | *Revisar* desde una IP chilena (pod en el cluster); si no hay RSS, entra por alertas de correo |
| LinkedIn / Indeed | — | — | Prohíben automatización | Solo sus **alertas por correo** leídas por IMAP (como dice el diseño) |

Otras que career-ops ya soporta y sirven para LATAM/remoto: Working Nomads, Welcome to the Jungle, Landing.jobs,
Computrabajo (parser HTML: revisar términos), Teamtailor, Recruitee, Personio, SmartRecruiters, BambooHR, Breezy.

## Ajustes recomendados al diseño

Numerados contra las secciones del documento.

1. **Ingesta → etapa 0 «vigencia»** (career-ops): antes de extraer o notificar, comprobar que la oferta sigue viva
   (el ATS devuelve 404/410 o la página ya no tiene botón de postular). Repetir al aprobar el paquete.
2. **Ingesta → extracción en cascada** (ApplyPilot): las APIs de ATS ya traen campos estructurados; para páginas de
   agregadores, leer `JobPosting` en JSON-LD antes de llamar a un LLM.
3. **Filtros duros → «no penalizar dato faltante»**: una oferta sin país o sin zona horaria pasa al LLM en vez de
   descartarse; descartar solo con evidencia explícita («US only», «EU residents», «no sponsorship» si aplica).
4. **Scoring → compuertas antes del número** (JobAppAgent): `excluir` (cerrada, inelegible), `preguntar` (falta un
   dato del usuario → pregunta por Telegram una sola vez y se guarda en `profile_answers`), `descartar` (seniority,
   familia de rol), `revisar` (pasa al resumen). El número se calcula **en código** desde la extracción: requisitos
   `met/partial/missing/unclear` con los IDs de `cv_facts` que los respaldan. El LLM no inventa el puntaje.
5. **Scoring → legitimidad aparte** (career-ops): reposteo de la misma oferta en 90 días, antigüedad, descripción
   genérica, enlace de postulación roto → etiqueta «fantasma probable» que baja la prioridad sin borrar.
6. **Scoring → confianza de la evidencia** (alta/media/baja) visible en Telegram junto al puntaje: separa «calza
   poco» de «no sé si calza».
7. **Modelos**: extracción con **Claude Haiku 5.5** vía Batches (nocturno) o en línea para alertas ≥ 85; qwen3.5:4b
   local como respaldo y para comparar en el set dorado. Embeddings **bge-m3** local (1024 dims, calza con
   `vector(1024)`); probar `qwen3-embedding:0.6b` (también 1024) porque el cruce es bilingüe (ofertas en inglés contra
   CV en español). Redacción con **Opus 5.5** (`effort` explícito); medir Sonnet 5.5 contra el set dorado de la
   fase 3 y quedarse con el más barato que no pierda calidad.
8. **Costo estimado** (precios de oct-2026): extracción ~USD 1–2/mes; redacción ~USD 0,15–0,25 por paquete con Opus
   5.5 (prefijo de reglas + hechos en caché) → con el tope de 5/día, USD 25–35/mes en el peor caso; la mitad con
   Sonnet 5.5. El tope mensual del diseño sigue siendo necesario.
9. **Opus 5.5 no acepta `temperature`**: la consistencia viene del esquema estricto + verificador, no de bajar la
   temperatura. Refuerza el invariante 2.
10. **Verificador → chequeo temporal**: además de cifras y tecnologías, que ningún logro se atribuya a otro cargo o
    periodo (el error más común según *Grounded Optimization*, arXiv 2607.01457).
11. **Postulación → aprobación ligada al paquete** (JobAppAgent): el botón Aprobar lleva un token de un solo uso con
    el hash de PDF + carta + respuestas, vence en 24 h, y el Remitente lo exige; `callback_data` de Telegram tiene
    tope de 64 bytes, así que el token vive en la BD. Registrar como «postulada» solo con confirmación visible (correo
    del ATS o página de éxito): **llenado ≠ postulado**.
12. **Postulación → duplicados y enfriamiento**: no repostular a la misma oferta (URL, ID del ATS, requisición) y
    avisar si es la misma empresa en menos de 15 días.
13. **Navegador asistido → neko** en vez de Xvfb + noVNC hecho a mano (WebRTC, fluido en el teléfono, Playwright por
    CDP). Para empezar, el CLI local `jh apply` sigue siendo lo más simple.
14. **Datos → pgvector ya está**: `vector` 0.8.6 disponible en `homelab-postgres` (imagen 17.11). Declararlo en el CRD
    `Database` con `spec.extensions`; no hace falta cambiar la imagen. Resuelve el «verificar» de la sección
    Despliegue.
15. **Observabilidad → scrape explícito**: el cluster no lee anotaciones; agregar un job `jobhunter` en
    `cluster/03-monitoring/monitoring/scrape.yml`.
16. **Fuentes → agregar HN «Who is hiring?»** y revisar Empleos Públicos desde el cluster.
17. **Seguridad**: las descripciones de ofertas son contenido no confiable; nunca cambian umbrales, herramientas ni
    destinatarios. Alertar si una oferta contiene instrucciones para un asistente.

## Stack recomendado (resumen)

Python 3.14, uv, ruff, pytest · FastAPI + uvicorn (panel Jinja + HTMX) · aiogram 3.31 (long polling, 1 réplica,
`Recreate`) · psycopg 3.3 + SQL plano · Procrastinate 3.10 (cola y periódicas; los «CronJob jh-fetch-*» del diseño
pueden ser tareas `periodic` del worker) · httpx + feedparser + selectolax · pgvector en `homelab-postgres` ·
anthropic 2.3 (Haiku 5.5 extrae, Opus 5.5 redacta) + Ollama (bge-m3) · Typst 0.15 o RenderCV 2.8 + `pdftotext` ·
Playwright 1.64 (+ neko en fase 4) · imapclient/aiosmtplib (iCloud) · structlog + prometheus-client · imagen en GHCR
privado, CI en GitHub Actions. Detalle y alternativas: `../stack.md`.

## Pendientes antes de implementar

- [ ] **Registry** (usuario): GHCR privado recomendado.
- [ ] Repo `koshiro/job-hunter` privado (el CV maestro es fixture del importador y tiene datos personales).
- [ ] Probar Empleos Públicos desde una IP chilena (pod del cluster).
- [ ] Confirmar IMAP/SMTP de iCloud con contraseña de app para el dominio propio.
- [ ] Decisiones abiertas del documento: empresas iniciales, lista negra, renta por defecto (USD y CLP).

## Fuentes consultadas

- career-ops: README, ARCHITECTURE.md, `modes/_shared.md`, `templates/portals.example.yml`, `docs/SUPPORTED_JOB_BOARDS.md`
- job-application-agent: README, SKILL.md, references/SOURCES.md, historial de commits
- ApplyPilot: README, CHANGELOG, historial
- [Ashby posting API (guía)](https://jobspipe.dev/blog/ashby-api-jobs) · [Get on Board API](https://www.getonbrd.com/help/what-can-i-do-with-get-on-board-s-api)
- [GitHub Packages: facturación](https://docs.github.com/en/billing/concepts/product-billing/github-packages)
- [CloudNativePG image volume extensions](https://cloudnative-pg.io/docs/1.30/imagevolume_extensions)
- [Grounded Optimization (arXiv 2607.01457)](https://arxiv.org/abs/2607.01457)
- [neko](https://github.com/m1k1o/neko) · [Selkies](https://github.com/selkies-project/selkies)
- [PgQueuer (EuroPython 2026)](https://programme.europython.eu/europython-2026/talk/RMY7Y7/) · [DBOS Transact](https://github.com/dbos-inc/dbos-transact-py)
- [JobOps](https://awesome.ecosyste.ms/projects/github.com%2FDaKheera47%2Fjob-ops) · [JobSpy review](https://jobspipe.dev/blog/jobspy-review.md) · [Resume-Matcher](https://hellogithub.com/en/repository/srbhr/Resume-Matcher)
- Versiones: PyPI y npm consultados el 2026-10-25; tags de Ollama en ollama.com/library
