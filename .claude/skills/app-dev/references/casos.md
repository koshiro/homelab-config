# Casos: apps ya hechas y lo aprendido

## Cyano Curve (arquetipo A) · `~/git/cyano` · https://cyano.danielriquelme.cl

Calibrador de curvas para negativos de cianotipia, 100 % en el navegador. Estado 2026-10-25: v0.2.0 publicada.

- **Stack**: SvelteKit 2.70 + Svelte 5 (runes) + TS 6, `adapter-static` con `fallback: 'index.html'` y
  `paths.relative: false` (el shell del service worker se sirve también en `/p/<id>`), Vitest 4, ESLint 10, Prettier.
  Dependencias de runtime mínimas: `@lucide/svelte`, `fast-png`, `utif2` (TIFF 16 bits).
- **Arquitectura**: `src/lib/core/` puro (sin DOM ni Svelte; todo cambio con tests), dominio y matemática ahí;
  `src/lib/ui/`, `steps/`, `i18n/`, `design/` aparte. Procesamiento pesado en Web Workers.
- **Calidad**: `npm run verify` = lint + `svelte-check --fail-on-warnings` + tests + build, obligatorio antes de cada
  commit y en CI (`.github/workflows/ci.yml`, que además sube `build/` como artefacto). Contraste de cada par de
  colores probado en ambos temas (`src/lib/design/contrast.test.ts`), WCAG 2.2 AA.
- **Diseño**: tokens OKLCH en tres niveles (primitivos → semánticos → componentes) en `src/app.css`; nada de hex/px
  sueltos; listbox accesible en vez de `<select>`; estados completos por control; revisión con un agente crítico de
  diseño antes de cerrar una pantalla.
- **Proceso**: 5 fases, un PR por fase (detección → interfaz → foto + PWA → despliegue), revisión de código al cierre
  de cada fase y documento de traspaso autocontenido para la fase de despliegue (`docs/FASE-5-DESPLIEGUE.md`).
  Prototipo previo en Python (tag `v0.1-python`) solo como referencia.
- **Despliegue**: sitio en pibot (sobrevive a la caída de Proxmox), nginx con CSP estricta, caché inmutable para
  `/_app/immutable/` y `no-cache` para `service-worker.js` y el manifest (`cluster/apps/cyano/configmap-nginx.yml`);
  publicar = `scripts/publicar.sh` (exige árbol limpio, `npm ci`, build, `rsync --delete`).
- **Lecciones**: separar el núcleo puro hizo posible testear la matemática sin navegador; el `add_header` dentro de un
  `location` de nginx anula los del `server` (por eso el include `.inc`); el service worker exige rutas absolutas.
- **Pendiente**: evaluar SvelteKit 3 / TS 7 / Vitest 5 (estables en oct-2026) con `sv migrate sveltekit-3`.

## SAC — Sistema de Análisis de Causas (arquetipo B, en diseño) · `~/git/SAC`

Análisis de carpetas investigativas penales con citas verificadas. Sin código aún; 11 ADRs.

- **Stack previsto**: FastAPI + workers, Postgres con pgvector + full-text español + RLS, objetos con hash por
  archivo, React + Cytoscape.js + PDF.js, modelos locales (OCR, bge-m3, extracción). Cola en Postgres (propuesta).
- **Decisiones reutilizables**: capa canónica de tokens por página y citas ancladas verificadas por código (ADR-0002);
  aislamiento por causa en la capa de datos, nunca en el prompt (ADR-0003); OCR sin descarte silencioso con cola de
  lectura dudosa (ADR-0004); bge-m3 elegido midiendo (ADR-0005); aserciones inmutables + aprobaciones tipadas
  (ADR-0007, 0009); capacidades explícitas por modelo (ADR-0010).
- **Lecciones del laboratorio OpenContracts**: un LLM local de 4B respondió 7/10 preguntas con 30–270 s por
  respuesta: suficiente para extraer y embeber, no para sintetizar (ADR-0011). Evaluar siempre contra un set dorado.

## Job Hunter (arquetipo B, en diseño)

Investigación completa del estado del arte, fuentes verificadas y recomendaciones sobre el documento de diseño:
`casos/job-hunter.md`. Qué portar del código de career-ops, JobAppAgent, ApplyPilot, JobOps y JobSpy (con archivo y
línea): `casos/job-hunter-codigo.md`.
