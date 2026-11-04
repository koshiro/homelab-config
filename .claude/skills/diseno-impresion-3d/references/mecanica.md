# Resistencia: anisotropía, fatiga, fluencia y admisibles

> Parte del informe de estado del arte (2026-11-03). Convenciones: `w` = ancho de línea (0.58), `h` = altura de capa (0.16), `s` = separación entre líneas. Ángulos de voladizo desde la vertical. Etiquetas de evidencia en `evidencia.md`. Lo marcado [I] es inferencia, no medición.

## Cálculo rápido

Toda pieza con carga sostenida, o cuya falla moleste, pasa por esto. Es una propuesta [I], no una norma.

1. **Dirección.** Si el esfuerzo cruza capas, se usa el valor Z. Si corre por el plano, el XY.
2. **Propiedad.** Valor de la ficha. Con marca desconocida, tomar el menor de la tabla de abajo: PLA 52, PETG 32, ABS 33,
   ASA 44 MPa en XY. Para Z aplicar la razón por material.
3. **Admisible.** `σ_allow = σ_dir × k_proc × k_env × k_time / SF`.
4. **Esfuerzo sobre las paredes**, sin contar relleno. En una sección de ancho `b` y espesor `t`, con pared `e` del slicer
   (1.67 con 3 perímetros, 2.76 con 5): `S ≈ b·(t³ − (t − 2e)³) / (6t)` y `A ≈ 2·b·e`.
5. **Margen.** `σ_allow / σ`. Si no alcanza: reorientar, luego subir perímetros, y al final engrosar.

Los perímetros son parte del diseño: declararlos en el informe de entrega.

| Factor | Valor sugerido [I] | Base |
|---|---|---|
| k_proc, valor Z de vendedor tal cual | 0.7 | Brecha vendedor-independiente, 0.66 frente a 0.50 |
| k_proc, razón Z ya aplicada o proceso propio calibrado | 0.85-0.9 | Dispersión 5-22 %; evita contar dos veces |
| k_proc, valor XY de ficha sin calibrar | 0.85 | Juicio; el proceso propio rinde algo menos que la ficha |
| k_env, temperatura ambiente | 1.0 | |
| k_env, cerca de HDT − 20 °C | 0.5 | Juicio; HDT es índice de flecha, no resistencia |
| k_env, nylon acondicionado, XY | 0.8 | PolyMide XY −22 % |
| k_time, estático corto | 1.0 | |
| k_time, carga sostenida | 0.15-0.3 | Rotura de PLA en Waseem; juicio |
| k_time, fatiga | 0.1-0.4 según ciclos | Curva Ezeh y Susmel, solo PLA |
| SF, no crítico, falla inofensiva | 1.5-2 | Juicio |
| SF, costoso o difícil de inspeccionar | 3 | Juicio |
| SF, posible lesión | No usar FDM sin ensayo calificado. Incluye lo que al soltarse pueda caer sobre alguien | Juicio |


**Ejemplo: gancho en J** [I]. 5 kg (49 N) sostenidos, PETG de marca desconocida, impreso de costado para que la tracción
corra por las capas. Brazo de 12 mm de espesor, 40 mm de ancho, radio interior 15 mm.

- Momento en la raíz: `M = F·(R + t/2) = 49 × 21 = 1030 N·mm`.
- Viga curva: la cara interior trabaja más que en viga recta. `r_n = t / ln(r_o/r_i) = 20.4`, excentricidad
  `e_c = (R + t/2) − r_n = 0.59` y `K_i = (r_n − r_i)·t / (6·e_c·r_i) ≈ 1.24`.
- Con 3 perímetros: `S = 600 mm³`, `A = 134 mm²`, `σ = 1.24·M/S + F/A ≈ 2.5 MPa`.
- Con 5 perímetros: `S = 810 mm³`, `A = 221 mm²`, `σ ≈ 1.8 MPa`.
- Admisible: `32 × 0.85 × 1 × 0.2 / 2 = 2.7 MPa`. Margen 1.1 con 3 perímetros y 1.5 con 5: pedir 5.
- De pie, con las capas cruzando el brazo, `σ_Z = 32 × 0.4` baja el admisible a 1.1 MPa y no pasa. Por eso se orienta primero.

## Evidencia

La razón Z/XY en tracción va de 0.29 a 0.89 y no es una constante del material. Las fichas de vendedor centran en 0.66 y los ensayos independientes en 0.50 [I], así que el valor de ficha es una cota superior [I]. El barrido más limpio dio PLA 63 MPa plano, 44 a 30°, 40 a 45°, 36 a 60° y 31 vertical, en CORE One a capa 0.2 ([CNC Kitchen 45°](https://www.cnckitchen.com/blog/stop-printing-flat-the-45-secret-for-stronger-parts)) [test]. Inclinar no sale gratis: en ese ensayo todas las impresiones inclinadas con soporte fallaron por warping, y un gancho inclinado no resistió más que uno de pie.

| Material y fuente | XY MPa | Z MPa | Z/XY | Alargamiento XY → Z % | Condición | Etiqueta |
|---|---|---|---|---|---|---|
| [PolyLite PLA](https://wiki.polymaker.com/polymaker-products/more-about-our-products/documents/technical-data-sheets/pla/polylite-tm-pla) | 52.3 ± 0.3 | 40.5 ± 0.5 | 0.77 [I] | s.d. | ISO 527, 100 % | [S] VENDOR |
| [eSUN PLA+ feb. 2026](https://www.esun3d.com/media/esun/catalog/certification/product/PLA_3KG1.75MM/PLA_-TDS-en.pdf) | 70.37 | 36.36 | 0.52 [I+] | s.d. | GB/T 1040 | leído, VENDOR |
| [PolyLite PETG V5.2](https://cdn.shopify.com/s/files/1/0789/2979/files/PolyLite_PETG_TDS_V5.2.pdf) | 31.9 ± 1.1 | 13.4 ± 2.0 | 0.42 [I] | 6.8 → 1.3 | ISO 527, 100 % | [V] VENDOR |
| [Prusament PETG](https://www.3dprintergear.com.au/assets/files/technical-data-sheet%20(1).pdf) | 47 ± 2 fluencia | 18 ± 4, método interno | 0.38 [I] | s.d. | "Vertical xz" 50 ± 1 es de canto, no Z | [V] VENDOR |
| [Prusament PETG V0](https://cdn.shopify.com/s/files/1/1745/6181/files/prusament-petg-v0-technical-data-sheet.pdf) | 39 ± 2 | 16.4 ± 1.3 | 0.42 [I+] | s.d. | ISO 527, adhesión entre capas | leído, VENDOR |
| [PolyLite ABS V5.6](https://polymaker.com/wp-content/uploads/lana-downloads/TDS_Polymaker_PolyLite-ABS_V5.6_2025-12-30_EN.pdf) | 33.4 | 29.7 | 0.89 [I] | 17.9 → 3.1 | Ficha con errores ("33.4 ± 92.7"), baja confianza | [V] VENDOR |
| [PolyLite ASA V5.1](https://cdn.shopify.com/s/files/1/0603/6609/files/PolyLite_ASA_TDS_V5.1.pdf) | 43.8 ± 0.8 | 32 ± 1.8 | 0.73 [I] | 6.7 → 1.65 | 24 h a temperatura ambiente | [V] VENDOR |
| [Bambu PETG-CF](https://cdn.shopify.com/s/files/1/0380/5149/files/Bambu_PETG-CF_Technical_Data_Sheet.pdf) | 59 ± 4 | 38 ± 3 (29 ± 4 en V3.0, vía buscador) | 0.64 [I] | 10.4 → 4.7 | 65 °C 8 h, boquilla 255 °C, 150 mm/s | [V] VENDOR |
| [Dogbones CNC Kitchen](https://www.cnckitchen.com/blog/the-influence-of-extrusion-temperature-on-layer-adhesion) | PLA ~60; PETG 55 | PLA 40; PETG 32 | 0.67; 0.58 [I] | s.d. | MK3, dasFilament, n=4, mejor temperatura | [V] INDEPENDENT-LAB |
| [Referencias estudio de sal](https://www.cnckitchen.com/blog/testing-the-strength-of-3d-prints-re-melted-in-salt) | PLA 61; PETG 55; ABS 40 | PLA 30-31; PETG 40; ABS 14 | ~0.50; 0.73; 0.35 [I] | s.d. | n no declarado | [V] INDEPENDENT-LAB |
| [Ganchos Prusament](https://www.cnckitchen.com/blog/comparing-pla-petg-amp-asa-feat-prusament) | PLA 73 kg; PETG 55; ASA 57 | PLA 40 kg; PETG 25; ASA 17 (20 con cerramiento a ~30 °C) | 0.55; 0.46; 0.29 | s.d. | MK3S, n no declarado | [V] INDEPENDENT-LAB |
| [Tesis CSUS](https://scholars.csus.edu/esploro/outputs/graduate/Mechanical-and-FEA-comparison-of-FDM/99258311232901671) | X supera a Z en 24.63 % PLA, 42 % ABS, 127.9 % PETG | | 0.80; 0.70; 0.44 [I] | s.d. | P1S, 100 %, capa 0.2 | [S] |

Valores por defecto cuando no hay ensayo propio [I]; son juicio del investigador, no norma.

| Material | Rango publicado Z/XY | Valor de diseño | Nota |
|---|---|---|---|
| PLA, PLA+ | 0.50-0.78 | 0.5 | Mejor retención relativa de impacto entre los rígidos |
| PETG | 0.38-0.73 | 0.4 | Mayor dispersión; depende mucho de la temperatura |
| ABS | 0.35-0.89 | 0.35 marco abierto, 0.5 cerrado | La fila 0.89 es de una ficha defectuosa |
| ASA | 0.29-0.73 | 0.3 marco abierto, 0.5 cerrado | Peor razón de impacto en Z (0.12) |
| PC, PC-ABS | 0.57-0.67 | 0.5 | Solo datos de vendedor |
| PA-CF, PETG-CF | 0.51-0.79 | 0.5 | Usar el valor Z directo si está publicado |
| PA-GF | 0.36 | 0.35 | Una ficha, solo fragmento |
| TPU | Sin tracción Z | Ensayar | Impacto 0.71 sugiere anisotropía leve |

La pérdida mayor no es de resistencia sino de tenacidad. El impacto ISO 179 de Bambu pasa de XY a Z en kJ/m² así: PLA 26.6 a 13.8 (0.52), PETG 52.7 a 13.6 (0.26), ABS 39.3 a 7.4 (0.19), ASA 41.0 a 4.9 (0.12), PC 34.8 a 9.0 (0.26) y TPU 95A 125.2 a 88.7 (0.71) ([guía Bambu](https://cdn1.bambulab.com/filament/a5e185aed14e6/filament-guide-en-4.pdf)) [V] VENDOR, un solo laboratorio. La causa sigue en debate entre difusión limitada y geometría de ranura a escala de filamento ([Allum 2020](https://hull-repository.worktribe.com/output/4511720/interlayer-bonding-has-bulk-material-strength-in-extrusion-additive-manufacturing-new-understanding-of-anisotropy)) [S]. Para el diseño da igual: una característica cargada en Z falla frágil y con poco aviso.

Las palancas tienen tamaños distintos, y este orden es una síntesis [I], no un estudio único. Primero la orientación, con factor 2 o más. Después el espesor de pared en mm: en ganchos de PLA sin relleno, doblar de 0.84 a 1.68 mm llevó de 139 N a 347-380 N, n=3 ([CNC Kitchen](https://www.cnckitchen.com/blog/big-nozzles-how-do-they-make-your-3d-prints-stronger)) [V] INDEPENDENT-LAB; con pared de 1.6 mm dio igual si eran 4 perímetros al 100 % (33 kg) o 2 al 200 % (39 kg) frente a 20 kg con 0.8 mm ([CNC Kitchen](https://www.cnckitchen.com/blog/the-effect-of-extrusion-width-on-strength-and-quality-of-3d-prints)) [V] INDEPENDENT-LAB. Por eso las paredes se especifican en mm. Después la temperatura de boquilla en el extremo bajo, en Z con n=4 ([CNC Kitchen](https://www.cnckitchen.com/blog/the-influence-of-extrusion-temperature-on-layer-adhesion)) [V] INDEPENDENT-LAB: PLA 20 MPa a 190 °C, 37 a 200, 39 a 210, 40 a 230, 37 a 250 y 32 a 270; PETG 18 a 200, 22 a 215, 30 a 230, 32 a 245 y 24 a 260. Con el techo de unos 240 °C del hotend con PTFE ([3dprinterly](https://3dprinterly.com/how-to-increase-the-max-temperature-on-a-3d-printer-ender-3/), vía buscador), PETG imprime cerca de ese máximo y no lo alcanza [I+]. Siguen el cerramiento para ABS y ASA (+20 % a unos 30 °C), el ancho de línea hasta cerca de 150 % de la boquilla (adhesión máxima ahí, Prusa MK2S, capa 0.16, n=3, misma fuente de ancho de extrusión), la altura de capa (de 0.1 a 0.3 mm: PLA −10 %, PETG −12 %, PETG-CF −21 %, ASTM D638 ([PMC10342851](https://pmc.ncbi.nlm.nih.gov/articles/PMC10342851/)) [V]), la densidad de relleno, que pesa más en fatiga (42.2 % y 72.4 % de contribución en ABS, 25-75 %, n=162 ([Domingo-Espin 2018](https://pmc.ncbi.nlm.nih.gov/articles/PMC6317007/)) [V]), y el patrón, bajo 5 % en tracción ([estudio 2016](https://redi.cedia.edu.ec/document/169645)) [S] SINGLE. El perfil del usuario está en 116 % de ancho y 32 % de capa, sobre el mínimo de un cuarto de boquilla ([CNC Kitchen](https://www.cnckitchen.com/blog/big-nozzles-how-do-they-make-your-3d-prints-stronger)) [V] INDEPENDENT-LAB, y sus 3 perímetros dan 1.67 mm por lado, justo en la zona de 1.6 mm de esos ganchos [I+].

Las entallas importan menos en el plano de lo que se cree. PLA plano al 100 % (0.1 mm, 30 mm/s, 4 mm de espesor) sostuvo 42.7-51.1 MPa de esfuerzo neto en tracción con radios de 0.5-3 mm, frente a UTS de 42.9 MPa, con distancia crítica L = 4.6 mm ([Ahmed y Susmel 2018](https://eprints.whiterose.ac.uk/123322/1/3D%20Printed%20PLA_TCD.pdf)) [V]. En fatiga la distancia baja a cerca de 0.5 mm a 2×10⁶ ciclos ([Ezeh y Susmel 2020](https://eprints.whiterose.ac.uk/158161/1/PLA_Notch_Fatigue_Accpeted%20Manuscript_LS.pdf), cálculo [I]) [V], y Kf medido a r = 2 mm fue 1.124 en entalla de borde y 1.155 en agujero, con pocas réplicas ([PMC12787623](https://pmc.ncbi.nlm.nih.gov/articles/PMC12787623/)) [V]. Una entalla CAD de radio 0 se imprimió con raíz de 0.15 ± 0.05 mm. Los agujeros taladrados superaron consistentemente a los impresos en PLA ([Kalyoncu 2026](https://lajss.org/index.php/LAJSS/article/view/8775)) [S]. Nada de esto se extiende a cargas entre capas ni a PETG, ABS o CF: no hay datos, y ahí conviene asumir Kt elástico completo [I].

La fatiga solo tiene una curva de diseño. Con 143 ensayos en PLA plano al 100 %, R de −1 a 0.3, 10 Hz, la curva para supervivencia sobre 90 % da k = 5.5 y σmax = 0.1·UTS a 2×10⁶ ciclos ([Ezeh y Susmel 2019](https://eprints.whiterose.ac.uk/146276/1/3D-printed%20PLA_plain%20Fatigue_IJFatigue.pdf)) [V]. Eso equivale a σmax/UTS de 0.40 a 10³, 0.26 a 10⁴, 0.17 a 10⁵, 0.11 a 10⁶ y 0.10 a 2×10⁶ [I]. En ABS a tracción R = 0.1, 1 Hz, de canto superó a vertical entre 2.8 y 41 veces, n=3 por celda, con nivel de esfuerzo no reportado ([PMC11509694](https://pmc.ncbi.nlm.nih.gov/articles/PMC11509694/), razón [I]) [V]. Usar 0.1·UTS en otros polímeros es supuesto conservador, no evidencia [I].

La fluencia es la laguna más seria. PLA con 15 MPa a 25 °C, ASTM D2990, rompió entre 1.188 y 2.250 h ([Waseem 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7764475/)) [V] SINGLE. PLA a 20 °C, unos 40 °C bajo Tg, bajo 10 N en flexión perdió módulo de fluencia hasta 1040 MPa tras 170 h, cerca de 56 % de los 1860 MPa de ficha, sin equilibrio ([arXiv 2302.11240](https://arxiv.org/abs/2302.11240)) leído. En unión atornillada M6 apretada a 5.07 N·m (2816 N de apriete, arandelas 12/7.5, 7 días), el par de retiro cayó 3.3 % en PLA y 11.5 % en PETG, con dos muestras por material ([Amza 2021](https://pmc.ncbi.nlm.nih.gov/articles/PMC8659210/)) [peer]; ese ensayo ponía unos 41 MPa bajo la arandela, cerca de la fluencia del PETG [I]. Regla de trabajo: esfuerzo sostenido en PLA a 10-15 % o menos de la UTS direccional [I], y carga sostenida al menos 20 °C bajo la HDT a 0.45 MPa [I].

El posproceso rara vez arregla Z. El recocido al aire da de +3.8 a +8 % en PLA y PETG y hasta +14.9 % en PETG-CF, con cambio medio de longitud de 3.55 mm (PLA), 3.33 mm (PETG, máximo 22 mm) y 0.28 mm (PETG-CF) en barra Tipo 1 ([PMC10342851](https://pmc.ncbi.nlm.nih.gov/articles/PMC10342851/)) [V]. En barras de 80 mm sin molde, 120 min, PLA varió −3.05 % en largo y +3.94 % en alto a 109 °C, y ABS −12.76 % y +15.53 % a 135 °C ([Lluch-Cerezo 2022](https://pmc.ncbi.nlm.nih.gov/articles/PMC9269357)) [V]. Refundir en sal lleva ABS de 14 a unos 35 MPa, pero exige 100 % de relleno, 2-4 h y enfriar de noche ([CNC Kitchen](https://www.cnckitchen.com/blog/testing-the-strength-of-3d-prints-re-melted-in-salt)) [V] INDEPENDENT-LAB. En yeso a 200 °C, 3 h, PETG de pie pasó de 36 a ~100 kg, pero el gancho hueco colapsó, y PLA perdió más de 30 % de carga ([CNC Kitchen](https://cnckitchen.com/blog/annealing-3d-prints-in-plaster)) leído. El epoxi sumó +1.2 %, sin significancia ([NAMRC](https://mtrc.utk.edu/wp-content/uploads/sites/45/2022/10/Surface-Treatments-NAMRC.pdf)) [S]. La fibra corta sube rigidez en XY pero no arregla Z: PA y PA/CF llegan a 26-28 MPa entre capas ([Dul 2021](https://link.springer.com/article/10.1007/S11665-021-05635-1)) [S], y el impacto Z baja 21 % de PETG a PETG-CF (cálculo [I] sobre fichas Bambu) [V] VENDOR.

No hay factor de seguridad de consenso para FDM de escritorio; el precedente riguroso son los valores B-basis de NCAMP para ULTEM 9085 ([presentación Wichita](https://www.amtas.washington.edu/wordpress/wp-content/uploads/2022/05/21.Andrulonis_Additive.pdf)) [S]. Ezeh y Susmel dan 22 MPa como referencia conservadora para PLA plano al 100 % sin ensayo ([paper](https://eprints.whiterose.ac.uk/id/eprint/142395/)) [V, abstract]. El método siguiente es propuesta del investigador [I], no norma: identificar qué esfuerzos cruzan capas, tomar la propiedad direccional, calcular sobre la sección de paredes si el relleno es ralo, y aplicar σ_allow = σ_dir × k_proc × k_env × k_time / SF.

La tabla de factores está en "Cálculo rápido", al inicio.

Ejemplo [I]: soporte de PETG cargado en Z con carga sostenida, XY de ficha 47 MPa, razón 0.4 (18.8 MPa), k_proc 0.85, k_time 0.2, SF 2: σ_allow cercano a 1.6 MPa. El número sale bajo a propósito: la respuesta correcta es reorientar, no engrosar. Los datos de flexión sobrestiman la tracción, con razones de 1.41 a 1.86 en fichas CF [I], así que no se debe dimensionar contra ellos. El FEA isótropo con admisibles direccionales basta en piezas planas de alto relleno, las propiedades ortótropas importan si la rigidez manda, y siempre conviene romper una pieza real, idealmente de 3 a 5 [I].
