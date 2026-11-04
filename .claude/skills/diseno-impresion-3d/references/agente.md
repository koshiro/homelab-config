# Reglas del agente, escaneo, conversión desde inyección y validación

> Parte del informe de estado del arte (2026-11-03). Convenciones: `w` = ancho de línea (0.58), `h` = altura de capa (0.16), `s` = separación entre líneas. Ángulos de voladizo desde la vertical. Etiquetas de evidencia en `evidencia.md`. Lo marcado [I] es inferencia, no medición.

La evidencia apoya lazos con pruebas ejecutables y mediciones del kernel, no la autoevaluación visual [I]. La guía de ScanRuler lo dice igual: "Numbers classify, renders locate", con `reverse_body_review` tras cada grupo de rasgos y cierre con `reverse_export_step { verify: true }` y `reverse_body_check` válido, cerrado y un solo sólido ([scanruler.com](https://scanruler.com), guía `scan-to-cad` §5, build 0.9.4). Esa guía da T para FDM de ±0.3-0.5 mm, con `T = max(valor del proceso, 3 σ del escaneo)`. La tabla es diseño del investigador y de este informe, sin validar; umbrales iniciales que la probeta reemplaza. Conviene parametrizar `w`, `h`, primera capa y `hole_offset` por material.

| # | Regla | Umbral en este perfil | Verificación | Base |
|---|---|---|---|---|
| 1 | Declarar función, carga, temperatura, ciclos y ambiente antes de modelar | Sin esto no se modela | Nota en el modelo | [I] |
| 2 | Filtrar material: seguridad, temperatura, UV, químicos, y al final rigidez | Usar la matriz; 20 °C bajo HDT 0.45 con carga sostenida | Lista de usos prohibidos | [I] |
| 3 | Orientar por camino de carga; la autoorientación es solo candidata | Avisar si el esfuerzo principal supera 30° respecto al plano de capa | Ángulo declarado frente a plano | [I]; Tweaker y Orca optimizan impresión, no carga |
| 4 | Si hay dos direcciones, partir antes que inclinar | Inclinar 45° da ~40 frente a 63 MPa y riesgo en cama móvil | Revisión de orientación | [test]+[I] |
| 5 | Paredes en espesores limpios | 1.13, 1.67, 2.22, 2.76, 3.31; avisar bajo 1.13; fallar bajo 0.58 si es funcional | `revisar_impresion.py` | [C]+[I+] |
| 6 | Rasgos finos según Arachne | Bajo 0.10 desaparece; 0.10-0.40 sale a 0.40; rasgo funcional no bajo 2.0; pin bajo 5 con filete o metal | `revisar_impresion.py` (`rasgo perdido`, `rasgo bajo el cordón mínimo`) | [C]+[I+]; [P] |
| 7 | Voladizo | Revisar sobre 45°; sobre 50° solo con torre; sobre 60° soporte o rediseño | `revisar_impresion.py`, áreas por ángulo desde la vertical | [I] |
| 8 | Puentes | Bajo 5 en cara que importa; hasta 10-15 ocultos; sobre 20 partir | `revisar_impresion.py`, zona sin apoyo y anclajes | [I]; 16 mm [C] como aviso duro |
| 9 | Agujero horizontal | Lágrima o rombo a 45°; taladrar si ajusta | Render de sección | [O]+[I] |
| 10 | Base | Chaflán 0.5 × 45° en bordes de cama que ajusten; nunca filete hacia la cama; caras móviles elevadas 2 capas | Área de primera capa | [I]; [D] |
| 11 | Rejilla de capas | Profundidades en múltiplos de 0.16; alturas desde cama en 0.20 + k·0.16 | Informativo | [I+] |
| 12 | Esquinas | Vertical 0.5 o más; 1 o más a fatiga; raíz 0.5 t o más | Revisión de radios | [I]; ver contradicción con Ahn |
| 13 | Agujeros verticales | +0.2 bajo Ø10; pasante libre de la tabla; nunca escalar la pieza | Tabla `offset(d, orientación, material)` | [I] |
| 14 | Ajustes | Tabla columna 0.5; probeta antes de la pieza | `reverse_body_clearance` | [I] |
| 15 | Fijación por defecto | Inserto si hay reensamble o par; directo solo con pocos ciclos y hasta 0.5-0.6 N·m en M3 | Tabla de insertos y pilotos | [test]+[I] |
| 16 | Rosca directa: eje de tornillo paralelo a Z. Un pasante queda como lo decida la orientación por carga | Si no, boss 3 d y piloto +0.1 | Revisión de orientación | [I] |
| 17 | Tuerca con carga hacia el material | Bolsillo inferior antes que lateral; 2 × m detrás; 3 líneas al lado | Sección | [test]+[I] |
| 18 | Apriete sobre plástico | Menos de 15-20 MPa bajo arandela; manguito si debe durar | Cálculo `F = T/(K·D)` | [I] |
| 19 | Roscas impresas | Nada bajo M8; `print45` si es plástico con plástico | Tabla; `scanruler.md` | [I] |
| 20 | Snap-fits y flexiones | En plano; ε repetida; L de 10 h o más; ninguno en Z; sin carga en reposo | Ecuación Bayer | [std]+[I]+[I+] |
| 21 | Bisagra viva | No portar en PETG, PLA o ABS salvo pocos ciclos | Tabla de necesidades | [peer]+[I] |
| 22 | Partir piezas | Pines para ubicar, adhesivo en caras anchas, perno si hay pelado | `reverse_body_clearance` | [I] |
| 23 | Resistencia | σ_allow con factores; re-orientar antes de engrosar | Cálculo a mano | [I] |
| 24 | Cierre | Sólido válido, cerrado, un cuerpo; rebanar y leer advertencias | `reverse_body_check`, `reverse_export_step { verify: true }` | Guía ScanRuler |

Los chequeos de voladizo, puente, isla, pared y lámina los hace `scripts/revisar_impresion.py` sobre el STL o 3MF exportado. `thickness_measure` y `scan_draft` miden escaneos, no sólidos.

Con piezas existentes, el escaneo es referencia para reconstruir CAD paramétrico. La guía pide `scan_qa` primero: `tiltDeg` mayor de unos 0.3° entre caras paralelas es culpa del escaneo o la alineación, y nada es fiable por debajo de 3 σ ([scanruler.com](https://scanruler.com), guía `scan-to-cad` §1). Luz estructurada cabe de sobra en T: Raptor Pro casi todo dentro de ±0.02 mm y Metro Y Pro dentro de ±0.03 mm con barras de bolas caseras, un solo autor ([CNC Kitchen](https://cnckitchen.com/blog/creality-raptor-pro-vs-revopoint-metro-y-pro)) leído. El LiDAR de teléfono no cabe: ±1 cm en objetos de más de 10 cm ([Sci. Reports 2021](https://link.springer.com/10.1038/s41598-021-01763-9)) [SNIPPET].

| Situación [I] | Ruta |
|---|---|
| Pieza prismática o inyectada, ajuste con otras | Reconstruir B-rep paramétrico |
| Superficie orgánica que debe calzar | Malla de contacto + `mesh_offset` + `mesh_shell`; el resto paramétrico |
| Mezcla | Superficie ajustada solo donde hace contacto; CAD en lo funcional |
| LiDAR de teléfono | Solo volumen general y posición, nunca ajuste |

`mesh_offset` mueve la superficie por su normal y no escala: una esfera de 20 mm expandida 0.5 queda en 21 mm y un agujero queda 1 mm más angosto ([ScanRuler](https://scanruler.com), esquema MCP). Valor de partida sobre escaneo orgánico: 0.2-0.4 mm más margen por deformación, con probeta [I]. Una pieza rota se aborda por función y cargas, lectura de fractura, escaneo y alineación por caras de contacto, modelado con intención, material y orientación antes de terminar, refuerzo del punto débil y validación [I]. La guía de ScanRuler indica cómo leer fractura, reconstruir el trozo perdido desde sus vecinos y marcarlo como inferido.

| Rasgo inyectado [I] | Por qué existe | Qué hacer en FDM, línea 0.58 |
|---|---|---|
| Nervio de 0.5-0.7 de la pared | Evita rechupes | Sin rechupes: 2 líneas o más (1.13 [I+]) y base mayor |
| Draft 0.5-3° | Desmoldeo | Quitar salvo que la cara acople con pieza con draft |
| Pared de 1-1.5 mm | Ciclo y material | Subir a 3-4 líneas (1.67-2.22 [I+]) si carga |
| Boss hueco con nervios | Rechupes | Boss macizo con inserto; agujero por escalera de probetas |
| Snap-fit | Elasticidad | Viga en el plano de capa; PETG mejor que PLA para varias veces, a verificar |
| Bisagra viva | PP orientado | No portar: pasador o pieza flexible aparte |
| Esquina viva interna | Herramienta | Radio mayor, sobre todo donde partió la original |
| Contrasalida | Corredera | Gratis si la orientación lo permite; si no, partir |

La validación va en secuencia [I]: probeta de capacidad una vez por perfil (voladizos, puentes, agujeros, paredes); calibre pasa/no pasa de ±0.1 mm; probeta del elemento crítico en la misma orientación; pieza completa escaneada; prueba de carga en dirección real; carga sostenida con referencia a 24 h y 7 días, y registro. En ScanRuler, `deviation_align` en modo `local` sobre datums, sin mejor ajuste en la comparación final porque oculta el offset, y clasificar cada zona ([scanruler.com](https://scanruler.com), guías `measure` §6 y `scan-to-cad` §5). La probeta recortada valida ajuste y forma local, no warping ni resistencia global [I]. Jadayel y Khameneifar (Ultimaker 3, PLA, capa 0.04, ATOS Core 200, NIST CTC-5) lograron unas tres veces menos desviación con cinco piezas promediadas, y menos de la mitad que con una sola, porque el error aleatorio entra a la compensación ([PolyPublie](https://publications.polymtl.ca/9400/1/2020_Jadayel_Improving_Geometric_Accuracy_3D_Printed.pdf)) leído. En pieza única: calibrar la máquina primero, imprimir de 3 a 5 veces solo la zona crítica cuando importe, y corregir parámetros del CAD por rasgo, sin deformar la malla [I]. Un adaptador inclinado se partió por quedar demasiado ajustado ([CNC Kitchen 45°](https://www.cnckitchen.com/blog/stop-printing-flat-the-45-secret-for-stronger-parts)) [test], así que la orientación entra en la probeta.

Para lotes, las reglas son cualitativas y no hay datos primarios de Slant, Prusa Farm ni 3DQue. Si cada pieza falla con p = 2 %, una cama de 10 sale limpia 82 % de las veces, con independencia simplista [I]. Una pieza fallida puede arruinar el lote ([Aniwaa](https://www.aniwaa.com/insight/3d-printers/10-things-learned-automated-print-farm/)) [SNIPPET], y Cancel object en Klipper no se verificó.
