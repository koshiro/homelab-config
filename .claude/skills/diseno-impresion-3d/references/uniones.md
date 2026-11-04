# Uniones, ajustes y mecanismos

> Parte del informe de estado del arte (2026-11-03). Convenciones: `w` = ancho de línea (0.58), `h` = altura de capa (0.16), `s` = separación entre líneas. Ángulos de voladizo desde la vertical. Etiquetas de evidencia en `evidencia.md`. Lo marcado [I] es inferencia, no medición.

Contenido: ajustes y holguras; insertos térmicos; tornillos directos; tuercas y precarga; roscas impresas; snap-fits; bisagras, flexiones y print-in-place; engranajes y eje-cubo; rodamientos, imanes y juntas; partir piezas. Para llevarlo a ScanRuler ver `scanruler.md`.

Para un tornillo pasante basta la tabla de `SKILL.md` y la sección siguiente. Lo demás se lee solo si la pieza lo usa.

## Cabezas, arandelas y fijación a una pared

Valores nominales de norma, de uso común en ingeniería y **no contrastados en esta investigación**: verificar con el herraje real.

| Tornillo | M2 | M2.5 | M3 | M4 | M5 | M6 | M8 |
|---|---|---|---|---|---|---|---|
| Cabeza cilíndrica ISO 4762, Ø | 3.8 | 4.5 | 5.5 | 7.0 | 8.5 | 10 | 13 |
| Cabeza cilíndrica, alto | 2 | 2.5 | 3 | 4 | 5 | 6 | 8 |
| Arandela ISO 7089, Ø exterior | 5 | 5 | 7 | 9 | 10 | 12 | 16 |

Asiento para cabeza: Ø cabeza + 0.6, profundidad alto + 0.3 [I]. `K` de `F = T/(K·D)`: 0.2 en acero seco, valor estándar de ingeniería.

Al fijar a una pared [I]:

- Una carga separada de la pared hace palanca: el tornillo de arriba tira con cerca de `F·a/b`, con `a` la distancia de la carga a la pared y `b` la del tornillo al punto de apoyo inferior. Subir los tornillos y dejar apoyo abajo reduce esa fuerza.
- La tracción del tornillo la aguanta el tarugo, no la pieza. Sin saber qué pared es no hay diseño cerrado: preguntarlo o escribirlo como supuesto.
- Cabeza plana con arandela, no avellanada, si el eje queda horizontal: el cono abre las capas.
- Dejar paso libre al destornillador.

Ninguna tabla publicada de ajustes merece confianza más allá de ±0.1 mm [I]. Toda columna "0.5" de esta sección es inferencia y debe confirmarse. En una Ender 3 con PETG DevilDesign (235 °C, 60 mm/s, 3 paredes, 20 % gyroid, boquilla no declarada), rodamientos en asientos a nominal, −0.1 y −0.2 necesitaron fuerza real: unos 200-250 N de meseta en Ø13 (lectura de curva), 583 N de pico en Ø12.8 y 588 N en Ø25.8, con curvas de 26/25.9/25.8 casi superpuestas hasta el último 1.5 mm ([Petrović 2024](https://scidar.kg.ac.rs/handle/123456789/21632)) [peer]. Es decir, a nominal ya hay prensa en PETG. En Ender-3 V2 con PETG, un hexágono de 6 entró libre a +0.1, difícil entre 0.1 y 0, y no entró a 0 ([Fab Academy](https://fabacademy.org/2025/labs/dilijan/students/zhirayr-ghukasyan/assignments/week05/)) [anecdotal].

### Ajustes y holguras

| Ajuste publicado (boquilla 0.4) | Valor | Fuente y calidad |
|---|---|---|
| Ajustado / snap cercano / deslizante o pivote | 0.2 / 0.3 / 0.4 de hueco | [Fictiv en Core77](https://www.core77.com/posts/65318/How-to-Design-Snap-Fit-Components) [vendor] |
| Holgura snap-fit FDM | 0.5 | [Hubs](https://www.hubs.com/knowledge-base/how-design-snap-fit-joints-3d-printing/) [vendor] |
| Holgura FDM general | 0.4-0.6, más en piezas grandes | [Sinterit](https://sinterit.com/?p=94623) [vendor] snippet |
| Defecto en la mayoría de rasgos | ~0.20 | [Digi-Key](https://www.digikey.at/en/maker/blogs/2026/10-smart-3d-printing-tips-tolerances-holes-and-slicer-tricks) [anecdotal] |
| Prensa a mano / mazo / tornillo de banco | 0.1-0.2 / 0.2-0.4 / 0.4-0.6 de interferencia | [Zbotic](https://zbotic.in/3d-printing-tolerances-designing-gaps-for-press-fits-threads-and-snap-fits/) [anecdotal] snippet |
| Pin impreso en agujero impreso | +0.3-0.4 giro libre; +0.1-0.2 ajustado | [Zbotic](https://zbotic.in/3d-printing-tolerances-designing-gaps-for-press-fits-threads-and-snap-fits/) [anecdotal] |
| PETG giro libre / suelto | 0.5-0.7 / 0.3-0.5 | [3dprintcalcs](https://3dprintcalcs.pages.dev/reference/common-tolerances) [anecdotal] snippet |
| Bisagra, pin en agujero | ~0.3 por lado (0.6 diámetro) | [Hex3D](https://hex-3d-gon.pages.dev/lessons/tolerance-005) [anecdotal] |
| Rieles y cajones | 0.3-0.5 por lado | [Hex3D](https://hex-3d-gon.pages.dev/lessons/tolerance-005) [anecdotal] |
| Deslizante / pestillo | 0.25 (0.20-0.35) / 0.3 (0.2-0.5) por lado | [BuildCAD](https://buildcad.ai/snap-fit-3d-printing) [anecdotal], sin fuentes |
| Compensación de agujero sobre nominal | PLA +0.2, PETG +0.3, ABS +0.4; suelto +0.2 más | [Rigid Prints](https://rigid-prints.pages.dev/design-guide/holes-bosses-threads) [vendor], sin ensayo |
| Agujero / pin vertical mínimo imprimible | Ø2 / Ø3 | [Rigid Prints](https://rigid-prints.pages.dev/design-guide/holes-bosses-threads) [vendor] |
| Agujero pasante M3 en piezas Prusa | 3.286 | [foro Prusa](https://forum.prusa3d.com/forum/english-forum-general-discussion-announcements-and-releases/designers-and-engineers-here-are-the-precise-dimensions-of-screw-holes-and-nut-pockets) [anecdotal] |
| Tolerancia de proceso | Escritorio ±0.3-0.5; industrial ±0.2 | [SPIROL](https://www.spirol.com/assets/files/inserts-for-3d-printed-assemblies-us.pdf) [vendor] |

| Valores de partida, diametrales salvo nota [I] | Boquilla 0.4, CAD | Boquilla 0.5, línea 0.58, CAD (factor ~1.3, no medido) |
|---|---|---|
| Metal a presión en agujero impreso, Ø10-30 | Nominal a −0.1 | Nominal, probeta de −0.1 a +0.2 |
| Impreso en impreso, prensa | −0.1 a −0.2 | −0.1 a −0.2 |
| Transición, empuje a mano | +0.1 a +0.2 | +0.15 a +0.25 |
| Deslizante sin juego visible | +0.2 a +0.3 | +0.3 a +0.4 |
| Giro libre | +0.3 a +0.6 | +0.4 a +0.7 (PETG arriba del rango) |
| Suelto, piezas grandes | +0.5 o más | +0.7 o más |
| Print-in-place, por lado | 0.25-0.4 | 0.35-0.45 |

| Agujero pasante [I] | M2 | M2.5 | M3 | M4 | M5 | M6 | M8 |
|---|---|---|---|---|---|---|---|
| Ajustado, eje vertical | 2.3 | 2.8 | 3.3 | 4.3 | 5.3 | 6.3 | 8.3 |
| Libre, usar este con boquilla 0.5 | 2.5 | 3.0 | 3.5 | 4.5 | 5.5 | 6.5 | 8.5 |

Qué escala con qué [I]: el ancho de línea rige pared, viga, nervio, módulo de engranaje, rosca mínima y hueco radial de print-in-place; la altura de capa rige profundidades, capas de puente y sacrificio, huecos en Z y bisagras planas; el herraje o la norma rigen inserto, tuerca, junta tórica y rodamiento, donde solo cambia la corrección del agujero. Todo ajuste de prensa, deslizante, de giro, inserto y piloto se calibra. Receta de probeta [I], una por material, boquilla y número de paredes: calibrar flujo y pressure advance y congelar el perfil; imprimir agujeros de nominal −0.2 a +0.5 en pasos de 0.1, a los diámetros reales, un juego con eje vertical y otro horizontal, con 15 mm o más de separación; imprimir pines iguales y un peine de huecos de 0.20 a 0.60 por lado; medir con el herraje real o vástagos de broca, no solo pie de rey; registrar primero libre, primero ajustado y primero a presión como `offset(d, orientación, material)`, y repetir al cambiar de marca de filamento. Existen probetas públicas de hole-size para insertos ([Printables](https://www.printables.com/model/1648510-hole-size-test-for-heat-set-inserts)) [test]. Un hueco bajo la resolución de la boquilla se funde: con 0.4, 0.05 mm se ignora ([MakerWorld](https://makerworld.com/en/models/107896-tollerance-test-3-grams)) [anecdotal] snippet.

### Insertos térmicos

El tamaño de agujero tiene una meseta ancha, y la calidad de instalación pesa más que la última décima. En M3×5.7 en PolySonic PLA, CORE One L, iron 240 °C, casi 50 insertos, 3 por diámetro, Ø3.6-4.6: unos 1400 N en agujeros chicos, caída lenta y luego abrupta; impreso, rebaba severa hasta 4.0, y **4.2 da asiento correcto con cerca de 90 % del máximo** ([CNC Kitchen](https://cnckitchen.com/blog/are-our-heat-set-insert-datasheets-wrong)) [test]. Una sola impresora y un solo material. Hay que medir aquí antes de adoptarlo [I].

| Ruthex ([M2-M5](https://www.3djake.com/ruthex/m2-m3-m4-m5-threaded-insert-assortment-box), [M6](https://www.3djake.com/ruthex/threaded-inserts-m6-25-pieces)) [vendor] | D1 moleteado | D2 | D3 agujero | L | W mín. |
|---|---|---|---|---|---|
| M2 | 3.6 | 3.1 | 3.2 | 4.0 | 1.3 |
| M3 | 4.6 | 3.9 | 4.0 | 5.7 | 1.6 |
| M4 | 6.3 | 5.5 | 5.6 | 8.1 | 2.1 |
| M5 | 7.1 | 6.3 | 6.4 | 9.5 | 2.6 |
| M6 | 8.7 | 7.9 | 8.0 | 12.7 | 3.3 |

La página no define las columnas: D3 como agujero y W como pared mínima son lectura del investigador, apoyada en los 4.0 "del manual" de CNC Kitchen.

| Receta, eje vertical [I] | Agujero CAD inicial | Rango de probeta | Ciego L+1 | Boss OD: regla W / 1.5× / 2× | Líneas de 0.58 para 1.5× |
|---|---|---|---|---|---|
| M2 | 3.4 | 3.1-3.7 | 5.0 | 6.2 / 5.4 / 7.2 | 2 |
| M3 | 4.2 | 3.9-4.5 | 6.7 | 7.8 / 6.9 / 9.2 | 3 |
| M4 | 5.8 | 5.5-6.1 | 9.1 | 10.5 / 9.5 / 12.6 | 4 |
| M5 | 6.6 | 6.3-6.9 | 10.5 | 12.3 / 10.7 / 14.2 | 4 |
| M6 | 8.2 | 7.9-8.5 | 13.7 | 15.3 / 13.1 / 17.4 | 5 |

Usar la regla W como defecto y 2× moleteado si importa el par; con línea de 0.58, de 4 a 5 perímetros cubren M3-M6 [I]. Ciego 1 mm más profundo que el inserto; pasante no más largo que él; fundir hasta cerca de 90 % y presionar a ras con herramienta ([CNC Kitchen](https://www.cnckitchen.com/blog/tipps-amp-tricks-fr-gewindeeinstze-im-3d-druck-3awey)) [test]. Hay conflicto sobre el chaflán: CNC Kitchen normalmente no lo usa y EPFL pide 0.3-0.5 ([EPFL](https://make.epfl.ch/wiki/public/spot_-_3d_printing/how_to_use_threaded_inserts)) [test].

| Otras marcas [vendor] | M2 | M2.5 | M3 | M4 | M5 | M6 | M8 |
|---|---|---|---|---|---|---|---|
| [McMaster](https://www.mcmaster.com/ultrasonic-inserts/), largo instalado corto / largo | 2.9 / 4.8 | 3.4 / 5.6 | 3.8 / 6.4 | 4.7 / 7.9 | 6.7 / 11.1 | 7.6 / 12.7 | |
| McMaster, agujero máx. con conicidad 8° | 3.0 / 2.7 | 3.86 / 3.58 | 5.05 / 4.70 | 5.74 / 5.28 | 7.70 / 7.06 | 8.86 / 8.15 | |
| [Tappex Multisert](https://www.fastenerdata.co.uk//pdf/TAPPEXBROCHURE2017.pdf), largo | 3.1 / 4.2 | 4.1 / 5.2 | 4.1 / 5.2 | 5.6 / 8.5 | 6.6 / 10.1 | 7.7 / 12.3 | 8.3 / 13.8 |
| Tappex, agujero | 3.0-3.3 | 3.7-4.0 | 3.7-4.0 | 5.4-5.9 | 6.0-6.5 | 7.7-8.2 | 10.2-10.6 |
| Tappex, profundidad | 3.2 / 4.3 | 4.2 / 5.3 | 4.2 / 5.3 | 5.8 / 8.6 | 6.8 / 10.2 | 7.9 / 12.5 | 8.9 / 14.0 |
| [Albany](https://www.albanycountyfasteners.com/media/64/3d/5a/1764619189/heat-set-insert-specs.pdf), agujero / OD / boss mín. | 3.2 / 3.5 / 5.0 | 3.7 / 4.0 / 5.5 | 4.0 / 4.6 / 6.5 | 5.3 / 6.0 / 8.5 | 6.4 / 7.1 / 10.0 | 7.6 / 8.4 / 11.5 | 10.2 / 11.1 / 15.0 |

Los McMaster corto y largo son insertos distintos, y no se reutiliza el agujero. El pie de Tappex menciona "MultiRiv", así que hay que confirmar la familia.

| Caso, M3 salvo nota | Extracción | Par de falla | Modo | Fuente |
|---|---|---|---|---|
| Ruthex, PLA, agujero 4.0 | 181 kg (1776 N) | ~3.5 N·m | Cabeza de tornillo | [CNC Kitchen](https://www.cnckitchen.com/blog/threaded-inserts-for-3d-prints-cheap-vs-expensive) [test] |
| eBay, PLA, agujero 4.1 | 157 kg (1540 N) | ~3.5 N·m | Cabeza; giró en ASA | igual |
| Inserto de moldeo barato, PLA, 4.5 | 39 kg (383 N) | ~3.5 N·m | Cabeza; inserto aguantó | igual |
| Tornillo directo, PLA, agujero 2.7 | 142 kg (1393 N) | ~1 N·m | Roscas | igual |
| Ruthex, PETG, 4 perímetros, 100 % | 119 kg (1167 N) | 3 N·m | Arrancado, giró | [CNC Kitchen](https://www.cnckitchen.com/blog/helicoils-threaded-insets-and-embedded-nuts-in-3d-prints-strength-amp-strength-assessment) [test] |
| Directo / Helicoil, PETG | 118 / 120 kg | 1 / 1 N·m | Roscas cortadas | igual |
| M6 INS 29L térmico, PETG / PLA / PC / PA6 30 % GF | ~5400 / ~5500 / ~3600 / ~7000 N | ~19 / ~24 / ~14 / ~22.5 N·m | s.d. | [SPIROL](https://www.spirol.com/assets/files/inserts-for-3d-printed-assemblies-us.pdf) [vendor], gráfico, 55 % relleno, 5 paredes, capa 0.16 |
| M6 INS 19L térmico, iguales | ~3700 / ~4300 / ~2800 / ~6000 N | ~13 / ~17.5 / ~10 / ~17 N·m | s.d. | igual |
| M6 INS 50 a presión, iguales | ~450 / ~750 / ~200 / ~950 N | ~11 / ~6 / ~6 / ~16 N·m | s.d. | igual |

En PLA con INS 29 M6 corto y 15 % de relleno, tracción y par suben con los lazos de pared: 1 lazo ~1000 N y ~4 N·m; 3, ~1950 y ~10; 5, ~2700 y ~14; 7, ~3350 y ~17; 9, ~3750 y ~19; 11, ~3900 y ~19.5. Con 2 lazos, pasar de 15 % a 95 % de relleno lleva de ~1850 a ~3500 N y de ~10 a ~17.5 N·m. SPIROL pide boss de 1.5× moleteado como mínimo y relleno sobre 50 %, y dice que hasta 70 % del desempeño depende de la instalación ([SPIROL](https://www.spirol.com/assets/files/inserts-for-3d-printed-assemblies-us.pdf)) [vendor], lectura a ojo. Tomar los valores de CNC Kitchen como últimos al 100 % y reducirlos de 2 a 3 veces con relleno de 15-20 % [I]. En PA12 SLS, M8×1.25 con 8 mm de enganche, n=5: rosca impresa 3409 N, inserto térmico 3827 N, Helicoil 4779 N ([PMC12787388](https://pmc.ncbi.nlm.nih.gov/articles/PMC12787388/)) [peer].

| Temperatura de instalación °C | PLA | PETG | ABS | Fuente |
|---|---|---|---|---|
| Impresión +10-20 °C | ~225 | ~245 | ~265 | [CNC Kitchen](https://www.cnckitchen.com/blog/tipps-amp-tricks-fr-gewindeeinstze-im-3d-druck-3awey) [test] |
| Hoja genérica, 2-4 s, enfriar 30-45 s | 177-204 | 218-246 | 204-232 | [Albany](https://www.albanycountyfasteners.com/media/64/3d/5a/1764619189/heat-set-insert-specs.pdf) [vendor] |
| Impresión +20 °C | 240-260 | | | [UW](https://medesignlab.me.wisc.edu/?p=162) [anecdotal] |
| Guía de taller | | 230 | | [EPFL](https://make.epfl.ch/wiki/public/spot_-_3d_printing/how_to_use_threaded_inserts) [anecdotal] |
| HDT +65 °C; iron típico 343-399 | | | | [SPIROL](https://www.spirol.com/assets/files/inserts-for-3d-printed-assemblies-us.pdf) [vendor] |

No funcionan bien en resina, que no funde: se pegan o presionan ([CNC Kitchen](https://www.cnckitchen.com/blog/how-to-use-threaded-inserts-in-resin-3d-prints)) [test]. Tampoco en TPU ([Rigid Prints](https://rigid-prints.pages.dev/design-guide/holes-bosses-threads)) [vendor]. En SLS rinden 20-50 % menos por microporosidad ([SPIROL](https://www.spirol.com/assets/files/inserts-for-3d-printed-assemblies-us.pdf)) [vendor]. El poster de CNC Kitchen con tablas M2-M8 se descargó pero no se pudo abrir, así que Ruthex lo sustituye.

### Tornillos directos en plástico

La extracción directa casi iguala a un inserto, pero el par no: en M3 falla cerca de 1 N·m, en PLA y en PETG, contra 3 a 3.5 N·m del inserto (tabla anterior). Las reglas de tornillos formadores son para plástico moldeado, no medidas en impresión.

| REMFORM, factores × diámetro nominal [std] ([catálogo](https://apexfasteners.com/fasteners/images/REMFORM.pdf)) | Enganche mín. | Enganche recomendado | Boss OD | Contrataladro × paso | Agujero |
|---|---|---|---|---|---|
| ABS | 1.5 | 2.5-3.5 | 2.0-2.5 | 0.25-0.50 | 0.72 |
| ABS/PC | 1.0 | 2.0-3.0 | 2.0-2.5 | 0.25-0.50 | 0.80 |
| PA 6/6.6 | 1.5 | 2.5-3.5 | 2.0-2.5 | 0.25-0.50 | 0.70 |
| PC | 1.0 | 2.0-3.0 | 2.0-2.5 | 0.25-0.50 | 0.80 |
| PET | 1.0 | 2.0-3.5 | 2.0-2.5 | 0.25-0.50 | 0.75 |
| PP | 2.0 | 3.0-3.5 | 2.0-2.5 | 0.25-0.50 | 0.70 |
| PS | 1.0 | 2.0-3.5 | 2.0-2.5 | 0.25-0.50 | 0.75 |

DELTA PT usa 0.8 × d, de 0.72 a 0.88 según material, y su contrataladro reduce esfuerzo de borde y rajaduras ([Bulten](https://www.bulten.com/media/b5eby1nc/deltapt-version-250422.pdf)) [std]. Hubs pide 75-80 % de enganche, pared igual al diámetro del tornillo, y taladrar el piloto tras imprimir ([Hubs](https://www.hubs.com/knowledge-base/how-assemble-3d-printed-parts-threaded-fasteners/)) [vendor].

| Tornillo d [I] | 0.8 d equivalente taladrado | Piloto CAD, eje vertical (0.8 d + 0.25) | Boss 2.5 d | Boss 3 d, eje horizontal | Enganche mín. 1.5 d | Objetivo 2.5 d |
|---|---|---|---|---|---|---|
| 2 | 1.6 | 1.85 | 5.0 | 6.0 | 3.0 | 5.0 |
| 2.5 | 2.0 | 2.25 | 6.25 | 7.5 | 3.75 | 6.25 |
| 3 | 2.4 | 2.65 | 7.5 | 9.0 | 4.5 | 7.5 |
| 3.5 | 2.8 | 3.05 | 8.75 | 10.5 | 5.25 | 8.75 |
| 4 | 3.2 | 3.45 | 10.0 | 12.0 | 6.0 | 10.0 |
| 5 | 4.0 | 4.25 | 12.5 | 15.0 | 7.5 | 12.5 |

La regla reproduce los 2.7 de CNC Kitchen y los 2.791 de piezas Prusa ([foro](https://forum.prusa3d.com/forum/english-forum-general-discussion-announcements-and-releases/designers-and-engineers-here-are-the-precise-dimensions-of-screw-holes-and-nut-pockets)) [anecdotal] para M3 [I]. Profundidad = enganche + 2 mm; contrataladro Ø = d + 0.1, 2 capas (0.32); ABS desde 0.72-0.75 d, PETG 0.75-0.8 d, PLA 0.8 d o más; límite de trabajo M3 directo 0.5-0.6 N·m y pocos reensambles [I]. Con eje vertical el esfuerzo de aro corre por perímetros continuos, y con eje horizontal abre interfaces de capa [I]; esto no tiene ensayo publicado y se razona desde datos de capa. Un usuario reporta que los autorroscantes aguantan hasta el sobreapriete y luego "splits layers" ([Makerforums](https://forum.makerforums.info/t/when-using-screws-in-a-part-what-is-better-thicker-or-thinner-layers/48981)) [O]. Si el eje horizontal es forzoso: boss mayor y piloto +0.1, con 3-4 perímetros y nervios [I].

### Tuercas cautivas y precarga

| ISO 4032 [std], vía [OMDL](https://royasutton.github.io/omdl-snapshot/docs/html/omdl-v1.0/group__database__component__fastener__iso__4032.html) | Paso | s | s mín. | e mín. | m máx. | m mín. |
|---|---|---|---|---|---|---|
| M2 | 0.4 | 4 | 3.82 | 4.32 | 1.6 | 1.35 |
| M2.5 | 0.45 | 5 | 4.82 | 5.45 | 2.0 | 1.75 |
| M3 | 0.5 | 5.5 | 5.32 | 6.01 | 2.4 | 2.15 |
| M4 | 0.7 | 7 | 6.78 | 7.66 | 3.2 | 2.9 |
| M5 | 0.8 | 8 | 7.78 | 8.79 | 4.7 | 4.4 |
| M6 | 1.0 | 10 | 9.78 | 11.05 | 5.2 | 4.9 |
| M8 | 1.25 | 13 | 12.73 | 14.38 | 6.8 | 6.44 |

Una tabla de vendedor lista M5 con 4.5 de alto, y DIN 934 difiere en algunos tamaños. Publicado: entre caras +0.2 y profundidad tuerca +0.4 ([Rigid Prints](https://rigid-prints.pages.dev/design-guide/holes-bosses-threads)) [vendor]; +0.2 alrededor ([Hubs](https://www.hubs.com/knowledge-base/how-assemble-3d-printed-parts-threaded-fasteners/)) [vendor]; M3 hexágono 5.456 entre caras con 2.4 de hondo y ranura cuadrada 5.600 × 2.150 ([foro Prusa](https://forum.prusa3d.com/forum/english-forum-general-discussion-announcements-and-releases/designers-and-engineers-here-are-the-precise-dimensions-of-screw-holes-and-nut-pockets)) [anecdotal]; 5.7 en OpenFlexure ([MR 371](https://gitlab.com/openflexure/openflexure-microscope/-/merge_requests/371/pipelines)) [anecdotal] snippet.

| Bolsillo [I] | Entre caras, boquilla 0.4 | Entre caras, boquilla 0.5 | Entre vértices, 0.5 | Profundidad, capas 0.16 | Capas |
|---|---|---|---|---|---|
| M2 | 4.2 | 4.3 | 4.97 | 2.08 | 13 |
| M2.5 | 5.2 | 5.3 | 6.12 | 2.40 | 15 |
| M3 | 5.7 | 5.8 | 6.70 | 2.88 | 18 |
| M4 | 7.2 | 7.3 | 8.43 | 3.68 | 23 |
| M5 | 8.2 | 8.3 | 9.58 | 5.12 | 32 |
| M6 | 10.2 | 10.3 | 11.89 | 5.60 | 35 |
| M8 | 13.2 | 13.3 | 15.36 | 7.20 | 45 |

Ranura lateral: ancho = entre caras de la tabla, alto = m +0.3, chaflán de entrada 0.5. Tuerca atraída por el tornillo: entre caras s a s −0.05, apta para PLA+ y PETG, no para paredes finas de ABS. Con línea 0.58 las esquinas internas redondean unos 0.29, así que conviene alivio de 0.3. Dejar al menos 2 × alto de tuerca de material detrás en la dirección de carga y 3 líneas al lado [I]. La dirección importa: en PETG, 4 perímetros, 100 %, 3 muestras, el bolsillo lateral falló a 86 kg (844 N) con la tuerca cortando limpio, y el inferior a unos 166 kg (1628 N), con par de falla cercano a 2 N·m ([CNC Kitchen](https://www.cnckitchen.com/blog/helicoils-threaded-insets-and-embedded-nuts-in-3d-prints-strength-amp-strength-assessment)) [test]. Para el techo del bolsillo, el puente escalonado original corta 0.2 y 0.4 mm ([Digi-Key](https://www.digikey.at/en/maker/blogs/2026/10-smart-3d-printing-tips-tolerances-holes-and-slicer-tricks)) [anecdotal], que aquí pasan a 0.16 y 0.32, modelados en CAD porque no se confirmó el ajuste en PrusaSlicer [I]. Para precarga, `F = T/(K·D)`: apuntar a menos de 15-20 MPa bajo la arandela, y usar manguito metálico, arandela elástica o reapriete a 24 h si el apriete debe durar [I]. Si es posible, el camino de carga debe saltarse el polímero [I].

### Roscas impresas

Las fuentes discrepan en el mínimo: bajo M5 evitar ([Hubs](https://www.hubs.com/knowledge-base/how-assemble-3d-printed-parts-threaded-fasteners/)) [vendor]; agujeros bajo 3.8 y postes bajo 2.0 ([Stratasys Direct](https://www.stratasys.com/siteassets/sdm/content---website-storage/design-guides/dg_sdm_fdm_0725a.pdf)) [P]; sobre M6 típicamente ([PMC12787388](https://pmc.ncbi.nlm.nih.gov/articles/PMC12787388/)) [peer]; M8 o mayor ([Rigid Prints](https://rigid-prints.pages.dev/design-guide/holes-bosses-threads)) [vendor]. Con línea de 0.58 un flanco M6 de 60° tiene alrededor de una línea de profundidad y el perfil colapsa [I]. Sobre orientación, en tornillos de PLA el mejor horizontal llegó a 16.4 N·m, dos veces el mejor vertical, y todas las fallas verticales siguieron capas, con banco tosco ([Hackaday](https://hackaday.com/tag/bolt)) [anecdotal]. En un cubo PLA+ con rosca interna 1/4-20, capa 0.2: 10 % de relleno 215 N, 25 % 300 N, 50 % 398 N, 100 % sobre 489 N ([Hackaday](https://hackaday.com/2023/11/10/putting-3d-printed-screw-threads-to-the-test)) [anecdotal].

| Rosca, boquilla 0.5, línea 0.58, capa 0.16 [I] | Valor |
|---|---|
| Mínimo práctico | M8 × 1.25; M6 solo carga ligera. Con `print45` de ScanRuler, que no enrosca con metal, desde unos Ø8 |
| Perfil preferido | Si es plástico con plástico, `print45` de ScanRuler (45°, Ø10×2.75); si no, trapezoidal 30°, Tr10×2 o Tr12×3; paso 2 o más; radio de cresta y raíz 0.2 |
| Holgura radial | 0.3-0.4 por flanco (0.2-0.3 con boquilla 0.4), añadida a la tuerca |
| Capas por paso | Al menos 8 (M8 × 1.25 da 7.8, justo bajo el mínimo; paso 1.5 da 9.4) |
| Eje paralelo a Z | Precisión y mejor montaje; la cortadura entre capas limita |
| Tornillo acostado | Dos veces o más de par; requiere plano y ajuste por prueba |
| Perímetros y enganche | 3-4; enganche 1.5 d o más; relleno 50 % o más en la zona |
| Entrada | Chaflán 45°, punta guía 1.0 |
| Mejor ajuste | Interno a broca de macho +0.1 y repasar con macho |

### Snap-fits

Las ecuaciones de Bayer aplican con la deformación limitada por la fluencia impresa ([Bayer](https://fab.cba.mit.edu/classes/S62.12/people/vernelle.noel/Plastic_Snap_fit_design.pdf)) [std]. Son para plásticos moldeados, con `y` = deflexión, `h` = espesor en raíz, `l` = largo, `b` = ancho, ε como fracción.

| Viga | Deflexión permisible |
|---|---|
| Sección constante | y = 0.67 ε l² / h |
| Espesor cónico a h/2 | y = 1.09 ε l² / h |
| Ancho cónico a b/4 | y = 0.86 ε l² / h |
| Fuerza de deflexión, las tres | P = (b h² / 6)(Es ε / l) |
| Fuerza de acople | W = P (μ + tan α) / (1 − μ tan α) |

Bayer limita los amorfos a cerca de 70 % de la deformación de fluencia, y el uso frecuente a cerca de 60 % del valor de una operación. Da μ de 0.50-0.65 para ABS, 0.45-0.55 para PC y 0.30-0.40 para PA sobre acero, con factor 1.2 a 1.5 sobre sí mismo. BASF advierte que las fórmulas clásicas valen sobre largo/espesor 10:1 y que la esquina viva viga-pared es la falla más común ([BASF](https://ulprospector.ul.com/1248/snapfit-3/)) [std]. Fictiv reduce 50 % la deformación admisible si la viga va en Z ([Core77](https://www.core77.com/posts/65318/How-to-Design-Snap-Fit-Components)) [vendor]. Hubs pide filete de al menos 0.5 × base, ancho de 5 o más y holgura FDM de 0.5 ([Hubs](https://www.hubs.com/knowledge-base/how-design-snap-fit-joints-3d-printing/)) [vendor]. Ahn muestra que un snap construido con el esfuerzo máximo a lo largo de los filamentos es mucho más fuerte ([Ahn 2002](https://iss.mech.utah.edu/wp-content/uploads/sites/103/2012/10/Ahn-Anisotropic_material-2002.pdf)) [V].

| Deformación de diseño [I] (0.7 × fluencia impresa, 60 % Bayer, 50 % Fictiv; no medida en snap-fits) | Fluencia usada | Una vez, plano | Repetido, plano | Una vez, en Z | Repetido, en Z |
|---|---|---|---|---|---|
| PETG | 5 % ([Prusament](https://filament2print.com/en/pet-petg-cpe/3427-prusament-petg-.html), snippet) | 3.5 % | 2.1 % | 1.8 % | 1.0 % |
| PLA, PLA+ | 3.2 % (Prusament PLA, snippet) | 2.2 % | 1.3 % | 1.1 % | 0.7 % |
| ABS | 4 % (3-5 % según [FindNStart](https://findnstart.com/learn/tracks/designing-for-3d-printing/designing-snap-fits), baja calidad) | 2.8 % | 1.7 % | 1.4 % | 0.8 % |

**Las columnas en Z no son seguras.** PolyLite PETG da 1.3 % de alargamiento en Z ([TDS](https://cdn.shopify.com/s/files/1/0789/2979/files/PolyLite_PETG_TDS_V5.2.pdf)) [V] VENDOR, por debajo del 1.8 % de una vez y cerca del 1.0 % repetido, y PolyMax PLA da 1.36 % ([TDS](https://cdn.shopify.com/s/files/1/0789/2979/files/PolyMax_PLA_TDS_V5.1.pdf)) [V] VENDOR. La nota de uniones valida su 1.8 % con un dato Prusament decodificado de un PDF con texto dañado (30 ± 5 MPa, 2.5 %), que otras dos notas contradicen con 16-18 MPa entre capas. Regla: **ningún snap con viga en Z** [I+]. Las referencias sin ensayo van de PETG 1.5-2.0 %, ABS 1.2-1.8 %, PLA 0.5-0.8 % ([FindNStart](https://findnstart.com/learn/tracks/designing-for-3d-printing/designing-snap-fits)) a plano/Z PLA 2/1 %, PETG 3/1.5 %, ABS 3/1.5 % ([BuildCAD](https://buildcad.ai/snap-fit-3d-printing)) [anecdotal].

| Caso [I], h = 1.74, L = 17.4 | ε | y constante | y cónico |
|---|---|---|---|
| PETG plano, repetido | 2.1 % | 2.45 | 3.99 |
| PLA+ plano, repetido | 1.3 % | 1.52 | 2.47 |
| ABS plano, repetido | 1.7 % | 1.98 | 3.23 |
| PETG en Z, repetido (no usar) | 1.0 % | 1.17 | 1.90 |

Receta [I]: brazo en el plano XY, impreso de costado; `h` en líneas enteras; L de 10 h o más; b de 5 o más; filete de raíz de 0.5 h o más; socavado de 1.0 o más con boquilla 0.5; holgura lateral de 0.3-0.5; viga sin carga en reposo por fluencia. La tabla usa `h` nominal de 3 × 0.58; con el espesor limpio de 1.67 los valores bajan 4 % [I+]. Ejemplo de fuerza: PETG, b 8, h 2, L 20, Es 1500, ε 2 %: P = 8 N; α 30° y μ 0.6 da W = 14.4 N; retención a 45°, 32 N; a 90°, permanente [I]. No hay ensayo revisado por pares de ciclos a falla de snaps impresos, y PLA+ no tiene definición estándar: tratarlo como PLA hasta probarlo [I].

### Bisagras vivas, flexiones y print-in-place

PETG, PLA y ABS no son bisagras vivas reales. En la única comparación controlada, 180° a 2.22 Hz, 0.25 de capa, 2 cáscaras, 100 %, zona de pliegue 1.5 × 1.0 × 25, prepliegue 10 veces a 80 °C, n=5 ([Balderrama-Armendariz 2016](https://utw10945.utweb.utexas.edu/sites/default/files/2016/188-Balderrama-Armendariz.pdf)) [peer]:

| Material | Ciclos, media ± DE | Carga antes de deformar, kgf | Carga axial máx., kgf |
|---|---|---|---|
| PETG | 856.6 ± 92.6 | 6.86 | 66.90 |
| PLA | 163.2 ± 29.8 | 6.30 | 80.62 |
| Nylon 12 | 198.8 ± 57.3 | 6.56 | 66.56 |
| PP | 1,071,928 ± 57,456 | 4.70 | 29.91 |
| TPU | Más de 2,000,000, detenido sin daño | 0.59 | 27.26 |

En PLA, plano dio 208.3 y 197 ciclos, y de pie 144.7 y 105.7: la orientación importó y el raster menos. Hubs dice construir la bisagra capa a capa, a menudo vertical, con nylon 12 en 0.4-0.6 y unos 25 ciclos ([Hubs](https://hubs.com/knowledge-base/how-design-living-hinges-3d-printing)) [vendor], lo que choca con ese resultado. No hay datos de ABS.

| Necesidad [I] | Receta |
|---|---|
| Pocos pliegues | PETG 0.64 (4 capas), meseta 1.5, plano, hilos cruzando el pliegue, preflexar 10 veces en tibio |
| Cientos de pliegues | PETG 0.96 (6 capas), unos 800 ciclos a 180° en clase 1 mm; pasador más allá |
| Miles o más | PP, TPU o pasador |
| Flexión elástica | Viga a flexión pura con ε de la tabla de snap-fits |

Dimensionado por flexión pura [I]: `ε = tθ/(2L)` o `ε = t/(2R)`. PETG t = 1.16, θ = 30°, ε = 2 %: L = 15.2 y R de 29 o más. Para ε = 1 %, L se dobla. PLA+ a 1 % o menos, ABS a 1-1.5 %, viga en XY, filete de raíz de 0.5 t o más. Biestables: un interruptor PETG se desgastó bastante rápido ([MakerWorld](https://makerworld.com/models/1185145)) [anecdotal] snippet.

Para print-in-place los valores son reportes de makers: 0.30-0.40 por lado ([Sovol](https://www.sovol3d.com/blogs/news/print-in-place-3d-printing-how-to-design-hinges-joints-and-moving-parts-that-actually-work)), unos 0.3 ([Hex3D](https://hex-3d-gon.pages.dev/lessons/tolerance-005)) y 0.25 en PLA con 0.4 ([MakerWorld](https://makerworld.com/models/3043371)), todos [anecdotal]. Los pines cónicos a unos 45° apoyan ambas caras ([Onshape](https://forum.onshape.com/discussion/28308/not-sure-what-im-doing-wrong-print-in-place-box-w-hinged-lid)) [anecdotal].

| Bisagra cónica [I] | Boquilla 0.4 | Boquilla 0.5, línea 0.58, capa 0.16 |
|---|---|---|
| Medio ángulo de cono | 45° desde el eje vertical, eje de bisagra en XY | Igual |
| Hueco radial en cono | 0.3 | 0.4 |
| OD de nudillo | 6-8 | 8-10 |
| Base del cono Ø | 3 o más | 4 o más |
| Hueco entre nudillos, axial | 0.3-0.4 | 0.4-0.5 |
| Hueco Z bajo voladizo plano | 2 capas | 0.32, más 0.10 si tiene techo |
| Pared de nudillo | 3 líneas o más | 1.74 nominal (1.67 limpio [I+]) |
| Contacto con cama | Elevar caras móviles 2 capas o chaflán 0.5 | Obligatorio con compensación 0 |

Pin cilíndrico en Z: hueco radial 0.4 con labio de retención. Pin cilíndrico horizontal: cae por combado de corona, así que usar lágrima a 45° y hueco 0.4. PETG tiende a hilar: tomar el extremo alto y liberar en tibio. Imprimir antes una probeta con 0.3, 0.35, 0.4, 0.45 y 0.5 [I].

### Engranajes y unión eje-cubo

El mínimo sin socavado con 20° son 17 dientes ([KHK](https://khkgears.net/new/gear_knowledge/gear_technical_reference/involute_gear_profile.html)) [std]. En PLA m = 3, 21 dientes, Sidewinder X2, PrusaSlicer, capa 0.1-0.2: desviación de Ø de cabeza −0.449 a −0.072, de pie −0.392 a −0.083, de agujero −0.126 a −0.01 ([Egyed y Faluvégi](https://real.mtak.hu/242057/1/MTK20-EN-03-Egyed-Faluvegi.pdf)) [peer]. En FZG, piñón m = 6, 17 dientes contra St37, 0.4, capa 0.2, 100 %, 1.5 N·m, 900 rpm: vida PETG +22.3 % sobre PLA y +37 % sobre ABS, con orden de desgaste internamente incoherente en el paper ([PMC9147857](https://pmc.ncbi.nlm.nih.gov/articles/PMC9147857/)) [peer]. La regla de 10× de Fictiv pide módulo cercano a 5 con tolerancia de 0.5 ([Fictiv](https://www.fictiv.com/articles/mechatronica-3d-printing-gears-and-robots)) [vendor], lo que por proporción daría 2.5 con 0.25 calibrado [I+]: módulo 2 queda en el límite optimista.

| Módulo [I] | Espesor en línea primitiva (π m / 2) | Líneas de 0.58 | Veredicto |
|---|---|---|---|
| 1.0 | 1.57 | 2.7 | Evitar: puntas bajo 2 líneas |
| 1.5 | 2.36 | 4.1 | Límite inferior |
| 2.0 | 3.14 | 5.4 | Recomendado |
| 2.5 | 3.93 | 6.8 | Con carga |
| 3.0 | 4.71 | 8.1 | Uso pesado |

Receta [I]: 17 dientes o más, o corrimiento `x = 1 − z/17`; reducción de espesor por holgura 0.15-0.20 con boquilla 0.5; ancho de cara 8-12 × módulo; imprimir plano, eje paralelo a Z; dientes sólidos; PETG primero para cargas bajas; pareja de acero si se puede; agujero CAD sobre eje con eje vertical: prensa +0.1, deslizante +0.25, giro +0.4, para eje de 5 mm de 5.2 a 5.3.

| Interfaz eje-cubo [I] | Valor inicial | Notas |
|---|---|---|
| Eje D Ø5, plano a 4.5 | Redondo 5.25, plano 4.75 | Plano en contacto, prisionero sobre el plano |
| Eje hexagonal | Entre caras +0.15 a +0.25 | Esquinas con alivio de 0.3 |
| Prisionero M3 | Inserto 4.2, piloto 2.65 o tuerca cautiva | 2 a 90° si importa el par |
| Chavetero | Ancho de chaveta +0.2 | Chaveta metálica, pared 2 × profundidad |
| Cubo de apriete | Partido + perno pasante M3 | Evita aflojamiento por fluencia |

### Rodamientos, bujes, imanes, juntas y estanqueidad

| Asiento 608, boquilla 0.5, PETG o PLA+ [I] | Agujero CAD | Notas |
|---|---|---|
| Prensa directa | 22.0, probeta 21.9-22.3 | Pico esperado 200-300 N; empujar solo anillo externo |
| Deslizante + pegamento | 22.2-22.3 | CA o retenedor |
| Nervios de aplastamiento | 22.3-22.4, 6 nervios de 0.6 × 0.25, chaflán 0.5 | Razonado desde 1 línea, no medido; solo cargas radiales ligeras |

Asiento general: OD +0 a +0.1 prensa, +0.2-0.3 pegado, pared de 3 mm o 5 líneas y hombro de 1 mm, con eje vertical por redondez [I]. Los nervios de aplastamiento perdonan variación a escala de 0.1 pero no sirven para reensamble ([Hackaday](https://hackaday.com/2020/10/15/adding-crush-ribs-to-3d-printed-parts-for-a-better-press-fit)) [anecdotal]. No hay fuerza de retención medida.

Los bujes impresos rinden poco sin filamento específico. En ensayo igus (0.11 MPa, 0.34 m/s, 370 de carrera, 3 semanas, eje de aluminio): ABS FDM 13.3 µm/km, i180 FDM 0.8, i3 SLS 0.4, iglidur J moldeado 0.2 ([igus](https://www.igus.co.uk/info/3d-print-tribology-test)) [vendor]. Los rankings PLA frente a ABS se contradicen entre estudios ([PMC12298762](https://pmc.ncbi.nlm.nih.gov/articles/PMC12298762/), [JMR&T 2026](https://doi.org/10.1016/j.jmrt.2026.02.218)) [peer]. Receta [I]: agujero +0.3-0.4 con boquilla 0.5, mejor escariado; largo 1-1.5 D; quedarse muy bajo los 0.23 MPa·m/s de i180, por ejemplo 0.05 MPa·m/s, lo que para Ø8 × 8 con 20 N da p = 0.31 MPa y v bajo 0.15 m/s (360 rpm). Lubricar con PTFE, silicona o PAO; los ésteres destruyeron trenes de ABS ([Machine Design](https://www.machinedesign.com/archive/ensuring-plastic-and-lubricant-compatibility)) [std].

Imanes [I], a partir de [Bambu forum](https://forum.bambulab.com/t/perfect-flush-magnet-fit/205491) [anecdotal]: prensa Ø +0.1 con probeta de +0.1 a +0.3; pegado Ø +0.2 a +0.3; profundidad = imán + 0.16 en capas enteras, chaflán 0.5; embebido con cobertura de 3 capas o más (0.48).

| Junta tórica, cara estática [std] ([Apple Rubber](https://www.applerubber.com/src/pdf/table-b.pdf)) | G ancho | H profundidad | Compresión | H CAD a 0.16 [I] | Capas | G CAD [I] |
|---|---|---|---|---|---|---|
| 1.78 | 3.18 | 1.24 | 30 % | 1.28 | 8 | 3.2 |
| 2.62 | 4.32 | 1.91 | 27 % | 1.92 | 12 | 4.4 |
| 3.53 | 5.33 | 2.72 | 23 % | 2.72 | 17 | 5.4 |
| 5.33 | 7.62 | 4.29 | 19 % | 4.32 | 27 | 7.7 |

La tolerancia de profundidad de +0.13 queda bajo el ruido de FDM de escritorio, así que una ranura directa de impresora no es fiable [I]. Sirve para sello estático de baja presión, W de 2.62 o más, pernos cada 25-40 mm, fondo sin líneas radiales. Las ranuras impresas filtran por canales de capa ([OSUG](https://hackaday.io/project/20458-osug-open-source-underwater-glider/log/61097-waterproofing-problems)) [anecdotal]. Para la pared misma: 3-4 perímetros, +5-10 °C, multiplicador +5-10 %, capa bajo 60-65 % de boquilla ([Prusa KB](https://help.prusa3d.com/en/article/watertight-prints_112324)) [vendor].

### Partir piezas y unir

Un enclavamiento mecánico alinea, no resiste: en PLA el mejor sin pegar fue una junta en C de unos 7 MPa frente a 44.4 MPa del macizo, cerca de 16 % ([All3DP](https://all3dp.com/4/ditch-the-glue-researchers-find-c-shaped-joints-outperform-dovetails-in-pla-prints/)) [peer] snippet. La soldadura por rotación llegó a 93.16 % de eficiencia en ABS y PLA ([JAJP 2024](https://doaj.org/article/55e45834c01a448e98220b5a24a30734)) [peer] snippet. En adhesivos, epoxi 12.86 MPa fue el mejor en PLA ([UGM](https://etd.repository.ugm.ac.id/home/detail_pencarian_downloadfiles/296935)) [peer] snippet, y en PETG, epoxi y CA rompieron el PETG antes que la unión, con MMA y poliuretano al frente ([Hackaday](https://hackaday.com/2025/01/30/comparing-adhesives-for-gluing-petg-prints)) [test]. PrusaSlicer trae Cut con Plug, Dowel, Snap y Dovetail, sin guía de holgura ([Prusa KB](https://help.prusa3d.com/article/cut-tool_1779)) [vendor].

| Rasgo [I] | Boquilla 0.4 | Boquilla 0.5, línea 0.58 |
|---|---|---|
| Cola de milano, holgura por lado | 0.15-0.25 | 0.25-0.3 |
| Ángulo y raíz | 15-20°, radio 0.5 | Igual, raíz de 1 línea o más |
| Lengüeta y ranura | Lengüeta 3-4 líneas, profundidad 2×, hueco 0.2 por lado | Hueco 0.25 por lado |
| Pasador metálico | Pin +0.1 pegado, nominal prensa | +0.15, nominal prensa |
| Pasador de filamento 1.75 | Agujero 2.0 | Agujero 2.1 |
| Pines de alineación | 2 por unión, 3 líneas de pared, lo más separados posible | Igual |
| Hueco de pegado, epoxi o MMA | 0.1-0.2 | 0.15-0.25 |
| Soldadura con solvente | Tocando, lijar plano | Igual |

Las costuras van en zonas de baja tensión, con área pegada de 3 veces o más la sección del brazo más fino y las caras impresas en la misma orientación. Hay que achaflanar las caras 0.3-0.5 para que la pata de elefante no abra la unión. Si hay pelado, agregar perno o inserto a través de la costura [I]. Material: PLA+ con CA o epoxi, ABS con pasta de acetona, PETG con MMA, poliuretano o epoxi tras lijar [I].
