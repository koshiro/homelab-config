# <App>: guía para agentes

<Una o dos frases: qué hace, para quién, arquetipo (A estática / B servicio Python / C bot / D lote).>

## Reglas

- `<comando de verificación>` debe pasar antes de cada commit (B: `uv run ruff format --check && uv run ruff check &&
  uv run pytest`; A: `npm run verify`).
- GitHub Flow: ramas `feat/`, `fix/`, `chore/`, `docs/` desde `main`; un PR por fase; nada de push directo a `main` ni
  `--force`. Conventional Commits en español (`feat(<ámbito>): …`).
- Comentarios, documentación y textos visibles en español; identificadores en inglés.
- El núcleo de dominio (`src/<app>/core/` o `src/lib/core/`) es puro y todo cambio ahí lleva tests.
- Decisiones relevantes en `docs/adr/NNNN-*.md`. Stack por defecto y alternativas: skill `app-dev`.
- Dependencias estables con al menos dos semanas publicadas; versiones fijadas en el lock.
- <Invariantes propios de la app, p. ej. «ninguna acción externa sin aprobación del usuario», «nunca versionar datos
  reales».>

## Despliegue

Según `~/git/homelab-config/docs/DISENO-APPS.md` (§<x>). Los manifiestos viven en ese repo
(`cluster/apps/<app>/`), no aquí. Flux aplica `main` de homelab-config: mergear allí es desplegar.
