# Job Hunter: revisión de código de los proyectos existentes (2026-10-25)

Clonados y leídos (sin ejecutar) a la fecha: career-ops `f4d7477`, job-application-agent `6f36e3d`, ApplyPilot
`4a8d521`, JobOps `664d9d2`, Job-apply-AI-agent `ee23c1e` y `python-jobspy` 1.4.1 (sdist). Para cada pieza de Job Hunter:
qué lógica ya está validada, dónde está y qué ajustar. Rutas relativas a cada repo.

## Licencias: qué se puede copiar

| Proyecto | Licencia | Uso permitido |
|----------|----------|---------------|
| career-ops | MIT | Portar código con atribución (comentario con origen y commit) |
| job-application-agent | MIT | Portar código con atribución |
| python-jobspy | MIT | Dependencia o portar el módulo de LinkedIn (~250 líneas) |
| ApplyPilot | AGPL-3.0 | Solo ideas; reimplementar, no copiar |
| JobOps | AGPL-3.0 + Commons Clause | Solo ideas |
| Job-apply-AI-agent (imon333) | **sin licencia** (todos los derechos reservados) | Solo ideas |

## 1. LinkedIn (pedido explícito del usuario)

**Job-apply-AI-agent** (`job_apply_ai/scraper/linkedin.py`, 248 líneas, último commit abr-2025): Selenium +
`undetected-chromedriver` abre `linkedin.com/jobs/search?keywords=…&location=…` **sin iniciar sesión**, hace scroll 3
veces y lee las tarjetas `.base-card` (h3 título, h4 empresa, `time[datetime]`); el detalle sale de
`h1.topcard__title` y `.description__text`. Problemas: un Chrome completo por cada oferta (lento y pesado), una sola
página (~25 resultados), sin pausas entre pedidos, user-agent de Chrome 91, sin manejo de bloqueo ni tests.

**Lo mismo, bien hecho: `python-jobspy`** (MIT, release 23-oct-2026, también lo usa JobOps). Sin navegador: pide los
fragmentos HTML que LinkedIn sirve a visitantes:

- Búsqueda: `GET https://www.linkedin.com/jobs-guest/jobs/api/seeMoreJobPostings/search` con `keywords`, `location`,
  `start` (de 10 en 10, tope 1000), `f_TPR=r<segundos>` (antigüedad), `f_WT=2` (remoto), `f_C` (empresas),
  `f_AL=true` (Easy Apply). Tarjetas `.base-search-card` con `data-entity-urn="urn:li:jobPosting:<id>"`.
- Detalle: `GET https://www.linkedin.com/jobs/view/<id>` → `.show-more-less-html__markup` (descripción),
  `.description__job-criteria-*` (seniority, tipo de empleo, función, industria), `.compensation__salary`.
- Pausa aleatoria de 3–7 s entre páginas; página vacía = `"<!DOCTYPE html>\n\n<!---->"`; si llegan tarjetas cero y
  no es esa página vacía → «bloqueado», se corta; si redirige fuera de `/jobs/view/` (authwall) → sin detalle.

**Verificado en vivo el 2026-10-25** (2 pedidos desde el pod): búsqueda `devops` + `Chile` + remoto → 200 con 10
tarjetas; detalle → 200 con descripción completa; sin JSON-LD `JobPosting`.

**Riesgo, honesto**: no usa la cuenta de Daniel, así que **no arriesga su perfil**. Sí incumple el User Agreement
de LinkedIn (8.2 prohíbe el scraping aunque sea de páginas públicas; en *hiQ v. LinkedIn* LinkedIn ganó por
incumplimiento de contrato en 2022). El riesgo práctico es que la IP de la casa reciba authwall o 429 para
visitantes. **Aprobado por el usuario el 2026-10-25** (nueva redacción del invariante 4 en `job-hunter.md`), con
estas condiciones:

- Adaptador propio en Python portando el de JobSpy (sin pandas ni su sesión rotativa): 3–5 búsquedas fijas
  (`f_WT=2`, `f_TPR=r86400`), cada 6–12 h, pausa 3–7 s, máximo ~10 páginas por corrida.
- Detalle solo para las que pasan el filtro de título (no las 100).
- Ante 429, authwall o «bloqueado»: cortar, no reintentar en 24 h y avisar por Telegram. Sin proxies ni evasión.
- Nunca login, cookies ni Easy Apply automatizado: la postulación sigue siendo manual.

## 2. Fuentes (career-ops `providers/`, 137 módulos, MIT)

Contrato: `{ id, detect(entry), fetch(entry, ctx) → Job[] }` con `Job = {title, url (clave de dedup), company,
location, postedAt?, description?, salary?, externalId?, requisitionId?, language?}` (`providers/_types.js`,
`ADDING_A_PROVIDER.md`). Portar a Python con la misma forma. Guardas que vale la pena copiar en todos:

- Host fijado + solo `https:` + `redirect: 'error'` (anti-SSRF) y validar que la URL de cada oferta sea del host
  esperado (`providers/getonbrd.mjs`, `_ip-guard.mjs`, `_safe-url.mjs`).
- Tope de páginas por fuente y **error si la respuesta no tiene la forma esperada** (`expected { data: [...] }`),
  nunca «0 ofertas» silencioso. Cursor repetido = error (`himalayas.mjs`).
- Fecha a epoch ms tolerando segundos/ms/string (`himalayas.mjs: toEpochMs`).

Datos concretos de las fuentes de Job Hunter:

| Fuente | Módulo | Detalle útil |
|--------|--------|--------------|
| Get on Board | `getonbrd.mjs` (197) | Feed por categoría, no la búsqueda: `/api/v0/categories/<cat>/jobs?per_page=100&expand[]=company&page=N` hasta página corta. Categorías para Daniel: `sysadmin-devops-qa`, `programming`, `machine-learning-ai`, `data-science-analytics`, `cybersecurity`. `published_at` en **segundos**; `remote: true` → «Remote», si no `countries[]` |
| Himalayas | `himalayas.mjs` (155) | `limit=20` + `cursor`; `applicationLink` como URL; `locationRestrictions` como ubicación |
| Greenhouse | `greenhouse.mjs` (280) | Tablero por slug; ubicaciones múltiples unidas con « · » |
| Lever | `lever.mjs` (133) | `descriptionPlain` trae la descripción gratis |
| Ashby | `ashby.mjs` (538) | Compensación normalizada (referencia de `salary`) |
| Workable | `workable.mjs` (345) | v3 por POST |
| HN Who is hiring | `hackernews.mjs` (252) | Algolia; parseo de comentarios |
| WWR / Remotive / RemoteOK / Jobicy / Working Nomads | 134 / 42 / 43 / 83 / 40 | Triviales |
| Computrabajo | `computrabajo.mjs` (219) | HTML; revisar términos antes |

## 3. Filtros sin LLM (career-ops `scan.mjs`)

- **Título** (`compiledPositiveMatchers`, `matchedTitleKeywords`): positivos (al menos uno) y negativos (ninguno),
  sin acentos ni mayúsculas (`foldTitle`); siglas de 2–3 letras con límite de palabra («AI» no calza en «maintain»);
  prefijos `word:` y `stem:`; `"a + b"` = todos los términos en cualquier orden.
- **Ubicación** (`buildLocationFilter`, l. 601): orden `block_hard` → `always_allow` → `block` → `allow` → título
  con «remote» como último rescate. Coincidencia por **límites de palabra Unicode** («india» no bloquea «Indiana»).
  **Dato faltante pasa** salvo `strict`. Para Daniel: `always_allow` = remote, anywhere, worldwide, latam, latin
  america, americas, south america, chile; `block_hard` = países que nunca sirven.
- **Elegibilidad por país en la descripción** (`buildCountryEligibilityFilter`, l. 917): frases excluyentes («must be
  located in the united states», «us-based candidates only», «authorized to work in the us») salvo que aparezca una
  inclusiva o el país del candidato.
- **Antigüedad** (`buildPostingAgeFilter`): sin fecha → pasa.
- Visa: listas de frases positivas y negativas (l. 1028) reutilizables si alguna vez importa.

## 4. Deduplicación (career-ops `scan.mjs`)

- URL normalizada quitando parámetros de tracking (`normalizeUrlForDedup`, `DEDUP_STRIP_PARAMS`).
- Clave `empresa::rol[@@lugares]` (`companyRoleDedupKey`, l. 2538): empresa canónica sin forma societaria
  (`CORPORATE_FORMS`, l. 1124), rol sin sufijos de lugar, «remote» ni etiquetas de género entre paréntesis o tras
  `|` (`normalizeRoleForDedup`, l. 2408), lugares separados por `; | · / or` pero **no** por coma.
- **El ID de requisición no identifica una oferta** (muchas ofertas por requisición: medido 181 → 118 en Affirm);
  solo sirve para separar dos ofertas con el mismo título.
- Historial con estados (`added`, `skipped_expired`…) y `recheck_after_days` para volver a mirar.
- Combinar con la similitud de embeddings del diseño solo como «posible duplicado», nunca para fusionar sola.

## 5. Vigencia de la oferta (career-ops `liveness-core.mjs`, 534)

Orden de decisión: HTTP 404/410 → vencida; **muro anti-bot → nunca «vencida»** (incierta); redirección a URL de
cerrada; patrones duros en el texto; página de listado; ¿hay control de «Postular»?; patrones blandos solo si no hay
control; contenido insuficiente. Normalizar antes de comparar (comillas tipográficas, sin tildes, espacios). Lección
central: **un falso «vencida» es caro** (la oferta desaparece para siempre), así que ante duda, «incierta».
Agregar patrones en español: «oferta cerrada», «ya no está disponible», «esta oferta ha (expirado|finalizado)»,
«proceso (cerrado|finalizado)», «no se reciben más postulaciones».

## 6. Puntaje

**JobAppAgent `scripts/job-application.mjs: scoreJob` (l. 988), determinista, portable casi tal cual.** Entrada:
la extracción del LLM (elegibilidad, estado de la oferta, seniority, familia de rol, modalidad, `mustHaves[]` con
`met|partial|missing|unclear` y evidencia). Compuertas en orden, cada una con su motivo:

1. Empresa excluida o «inelegible» → `exclude`; elegibilidad «unclear» → `ask`.
2. Oferta cerrada → `exclude`; estado «unclear» → `ask`.
3. Ubicación excluida → `exclude`; modalidad incompatible → `exclude` (sin especificar → `ask`).
4. Seniority fuera del objetivo → `skip` (sin especificar → `ask`).
5. Sin requisitos estructurados o alguno «unclear» → `ask`.
6. Cobertura = (met + 0,5·partial) / total; bajo el mínimo → `skip`.

Puntos: familia de rol 25, seniority 15, cobertura × 0,4, remoto/ubicación 10, industria 5, renta 5; si los años
pedidos difieren en más de 2 del perfil, tope bajo el umbral y revisión manual. Para Daniel: familia por prioridad
(DevOps 25, Backend 20, TI pública 15, AI 15), sin compuerta de renta (decisión del documento) y sin auto-envío.
`ask` = pregunta por Telegram que se guarda en `profile_answers`.

**career-ops `modes/_shared.md`** (puntaje holístico 1–5 por LLM; no lo copiamos) aporta dos cosas que van aparte del
número: **confianza de la evidencia** (Low si falta la descripción o el calce es desconocido o hay ≥ 2 dimensiones
desconocidas; Medium si alguna es parcial; High solo si todas están respaldadas; hasta 3 «chequeos que cambiarían la
decisión») y **legitimidad** (antigüedad <30 / 30–60 / >60 días, botón activo, especificidad técnica, realismo de
requisitos, reposteo ≥ 2 veces en 90 días, transparencia salarial), presentada sin acusar.

## 7. Verificador anti-invención

- **career-ops `verify-cv-facts.mjs`** (3.082 líneas, MIT): dos capas que nuestro verificador por IDs no cubre solo.
  (a) **Cifras**: extrae afirmaciones numéricas y las liga al **sustantivo más cercano** en una ventana de 4
  palabras («15+ years scaling teams» → «15 years»), con sinónimos («articles» = «guides»), moneda, multiplicadores
  («2x»), magnitudes (K/M) y números escritos; los años sueltos («en 2013») no cuentan. Toda cifra del documento
  generado debe existir en la fuente. (b) **Hechos no numéricos**: empleadores, cargos, herramientas en listas
  «Tecnologías:», autoría delegada («coordiné a un proveedor que construyó» ≠ «construí»), verbos inflados y
  adopciones no respaldadas; frases prohibidas por configuración. Tiene `--self-test` con las regresiones que ya
  les pasaron: copiar esos casos como tests y agregar vocabulario en español («años», «establecimientos»,
  «clientes», «estudiantes», «%», «s»).
- **ApplyPilot `scoring/validator.py`** (ideas): lista de clichés prohibidos («passionate», «spearheaded», «proven
  track record»…) y de **fugas del LLM** («here is the revised», «I apologize», «as requested») que delatan texto de
  máquina; normalizar rayas y comillas tipográficas. Hacer las equivalentes en español («apasionado», «proactivo»,
  «a continuación», «aquí está la versión»).

## 8. Aprobación y envío (JobAppAgent `scripts/review-batch.mjs`, 427, MIT)

- Lote de hasta 25 ítems; cada ítem guarda `sha256` de respuestas, del texto (correo/carta) y del CV.
- Al aprobar: `mac = HMAC-SHA256(secreto local, JSON canónico de {batchId, ítems aprobados con url y hashes,
  sha256 del CV, expiresAt, canal})`; token `rbt1.<batchId>.<mac>`; vence a las 24 h (también el lote pendiente).
- Al enviar (`verifyReview`): recalcular el MAC y comparar con `timingSafeEqual`; el ítem debe estar aprobado, **no
  usado** (`uses[itemId]`, una aprobación = un envío) y sin cambios; si el CV cambió → lote nuevo.
- Límite honesto que declaran: el código no puede impedir un clic directo en el navegador; protege los pasos
  propios (envío por correo, registro).
- Para Job Hunter: tabla `approvals` en Postgres con el MAC; el botón de Telegram lleva solo el `batchId` (64 bytes);
  el Remitente llama a la verificación antes de SMTP.

Otras piezas del mismo repo: «llenado ≠ postulado» (solo se registra con confirmación visible) y detección de
llenados sospechosos por huella repetida (`fillTelemetryFingerprint`); enfriamiento de 15 días por empresa con frase de
anulación explícita; bloqueos que piden a la persona (`AUTONOMY_HARD_STOPS`: autenticación, MFA, CAPTCHA, declaración
legal, datos demográficos, documento de identidad, autorización o renta ambiguas, afirmación no verificable).
**Corrección a la investigación anterior**: el repo trae `captcha-vendor.mjs` (CapSolver/2captcha) **apagado por
defecto**; no se porta (invariante 4).

## 9. Formularios asistidos

- career-ops `prepare-application.mjs` (255): lista blanca de hosts Greenhouse/Ashby/Lever, el PDF debe estar dentro
  del directorio de salida, **nunca hace POST**; imprime el prellenado y la persona envía. `modes/apply.md` (480)
  documenta el proceso campo a campo.
- ApplyPilot `apply/prompt.py` (624) y `apply/launcher.py`: prompt para que un agente llene formularios con
  Playwright MCP; útil como lista de casos (subir archivos, preguntas de selección, validaciones), quitando el paso
  de enviar.
- ApplyPilot `enrichment/detail.py`: cascada JSON-LD `JobPosting` (busca en `@graph` y listas; URL de postulación de
  `directApply`/`applicationContact`/`url`; descarta descripciones < 50 caracteres) → selectores de botón y
  descripción por ATS (`APPLY_SELECTORS`, `DESCRIPTION_SELECTORS`) → LLM. Reintentables 408/429/5xx; permanentes
  404/410/451; pausa por sitio (`SITE_DELAYS`).

## 10. Seguimiento por correo (JobOps)

`orchestrator/src/server/services/post-application/ingestion/email-router.ts`: un LLM recibe el correo (máx. 12.000
caracteres) y la lista numerada de postulaciones activas, y devuelve JSON con `isRelevant`, `bestMatchIndex` (solo de
la lista), `confidence` 0–100 y `stageTarget` ∈ {no_change, applied, recruiter_screen, assessment,
hiring_manager_screen, technical_interview, onsite, offer, rejected, withdrawn, closed}. Para Job Hunter: reglas por
remitente/ATS primero; lo demás con Haiku 5.5 y ese esquema; cambio de estado automático solo con confianza alta, si
no, pregunta por Telegram. Estados con alias en español: career-ops `templates/states.yml`.
