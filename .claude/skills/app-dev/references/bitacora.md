# Bitácora de la skill app-dev

| Fecha | Tarea | Qué faltó | Qué se agregó |
|-------|-------|-----------|---------------|
| 2026-10-25 | Crear la skill a partir de cyano y SAC + investigación de Job Hunter (estado del arte, fuentes en vivo) | No había un lugar con el stack decidido: cada app reinvestigaba | SKILL.md, stack/llm/integraciones/casos, `casos/job-hunter.md`, plantillas probadas con uv 0.13 (sync, ruff, ty, pytest). El Dockerfile no se probó: no hay Docker en el pod claude-remote; probarlo en el primer CI real |
| 2026-10-25 | Revisión de código de career-ops, JobAppAgent, ApplyPilot, JobOps, JobSpy y Job-apply-AI-agent | El README de JobAppAgent omitía su módulo de CAPTCHA: leer el código, no solo la documentación | `casos/job-hunter-codigo.md`, regla «estudiar = clonar y leer» en SKILL.md, LinkedIn de invitado verificado |
| 2026-10-25 | ¿Fork en vez de construir Job Hunter? | Descarté JobOps por licencia sin leer qué permite y elegí Python sin mirar el lenguaje del código reutilizable | Regla 0 «adoptar antes que construir; el lenguaje lo decide el código reutilizable»; revisión en `casos/job-hunter.md` |
| 2026-10-27 | investigacion: estudio del estado del arte, esqueleto, prototipo DBOS | ~40 | la plantilla violaba la regla de dos semanas | `exclude-newer` en la plantilla pyproject, caso en casos.md |
