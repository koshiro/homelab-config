# Integraciones

## Telegram (aiogram 3)

- **Long polling** desde el cluster: sin Ingress ni túnel. Implica **1 réplica + `strategy: Recreate`** (getUpdates no
  admite dos consumidores; patrón de `cluster/apps/minecraft/whitelist-bot/`).
- Lista blanca de `chat_id` en un middleware: todo lo demás se ignora y se registra.
- Botones: `callback_data` tiene **tope de 64 bytes** → guardar el estado en la BD y mandar un id corto
  (`CallbackData` tipada de aiogram). Responder siempre el callback (`callback.answer()`) o el cliente queda girando.
- Aprobaciones: el botón lleva un token de un solo uso ligado al **hash del paquete mostrado**, con vencimiento
  (24 h). Si el paquete cambió, el token no sirve y se vuelve a mostrar.
- Mensajes idempotentes: guardar `message_id` enviado por evento para no duplicar tras un reinicio.
- Reutilizar el bot de avisos del cluster solo para alertas; cada app tiene su propio bot (token en SOPS).

## Correo (iCloud con dominio propio, contacto@danielriquelme.cl)

- Apple no tiene API de correo: IMAP `imap.mail.me.com:993` (SSL) y SMTP `smtp.mail.me.com:587` (STARTTLS) con una
  **contraseña específica de app** (requiere 2FA). Usuario: la dirección de iCloud. *Revisar* al implementar.
- La contraseña abre todo el buzón: montarla en un solo Deployment, registrar cada envío y rotarla.
- Lectura: **imapclient** 4.1 (sync, simple) o **aioimaplib** 2.0 (async). Usar `UID` + `IDLE` o sondeo cada pocos
  minutos; marcar procesados por UID en la BD, no con flags del buzón.
- Envío: `smtplib`/`aiosmtplib`; tras enviar, `APPEND` a «Enviados» por IMAP (iCloud no siempre guarda copia del SMTP).
- Clasificar correos entrantes: reglas por remitente/asunto primero (ATS conocidos), LLM barato solo para el resto.

## PDF y CV

- **Typst** 0.15 (`pip install typst`, `typst.compile("cv.typ", sys_inputs={...})`): plantilla `.typ` + datos JSON;
  una columna, encabezados estándar, sin tablas ni íconos para que los ATS lean bien.
- **RenderCV** 2.8 (MIT): CV como YAML → Typst → PDF (+ Markdown/HTML). Útil si el generador produce YAML en su
  esquema; sus temas ya son de una columna.
- DOCX solo cuando se pida: Markdown → `pandoc` (o `python-docx`).
- Chequeo ATS: `pdftotext -layout` (poppler-utils en la imagen) → orden de lectura, contacto parseable, % de keywords
  literales. PDF siempre con texto, nunca imagen.
- HTML → PDF con Playwright (`page.pdf()`) si ya hay plantilla HTML (así lo hace career-ops).

## Fuentes públicas y scraping limpio

Orden de preferencia: **API JSON pública → RSS/Atom → JSON-LD (`schema.org/JobPosting`, `Product`…) en el HTML →
selectores CSS → LLM** sobre el texto. Cada nivel solo si el anterior no existe.

- `User-Agent` identificable, cadencia según los términos de cada fuente, `If-Modified-Since`/ETag, backoff ante
  429/5xx, guardar la respuesta cruda (jsonb) para reprocesar sin volver a pedir.
- Un adaptador por fuente con la misma interfaz y **error si la primera página trae tarjetas pero se parsean cero**
  (así un cambio de HTML se ve como error y no como «no hay ofertas»).
- Guardia SSRF si se siguen URLs de terceros: solo `http(s)`, sin IPs privadas, `follow_redirects` controlado.
- Respetar `robots.txt` y términos; nada de evadir Cloudflare/CAPTCHAs ni usar cuentas personales (LinkedIn prohíbe
  bots en su User Agreement).
- Catálogo de fuentes de empleo verificado en vivo: `casos/job-hunter.md` § Fuentes.

### Búsqueda web propia (SearXNG) — medido 2026-10-29
- Imagen `searxng/searxng:<fecha>-<sha>`, solo `formats: [json]`, `outgoing.proxies.all://` (curl_cffi) y bajar
  `search.suspended_times` a minutos. Al arrancar baja las listas de ClearURLs **sin proxy** (la NetworkPolicy lo corta).
- Desde una IP doméstica: brave → 429 con captcha; duckduckgo → CAPTCHA tras ~6 consultas y `unexpected crash` con
  `site:`; google y qwant → access denied; bing responde pero con resultados pobres. **No basar un flujo en la
  búsqueda gratuita**: URLs conocidas + enlaces de páginas oficiales primero; API de pago con clave si hace falta.
- Portal de Transparencia (CPLT) responde 403 a clientes automáticos; los códigos de organismo del CPLT se repiten en
  leylobby (`AP011` = SERVIU Araucanía; `MU339` = Municipalidad de Villarrica).

## Navegador asistido (humano en el bucle)

- **Playwright** prellena; la persona revisa y envía. Nunca pulsar «Enviar» por código en formularios de terceros.
- Remoto desde el teléfono: **neko** (`m1k1o/neko`, WebRTC, Chromium, varios participantes, Playwright conectado por
  CDP) en un Deployment que escala a 0 y solo por tailnet. Alternativa DIY: Xvfb + noVNC + Chromium (más simple, sin
  audio ni multiusuario). Selkies: pide mantenedores, no elegir.
- Arranque más simple: CLI local `app apply <id>` que abre Playwright con perfil persistente en el Mac.

## Secretos y configuración

Cada secreto en `secret.sops.yml` dentro de `solo-flux/` (skill homelab). La app los lee de variables de entorno o de
archivos montados; nunca en la imagen ni en ConfigMaps. Archivos de configuración de negocio (`companies.yaml`,
`profile_answers.yaml`) en un ConfigMap si no tienen datos sensibles, o en la BD si el usuario los edita desde la app.
