# Materiales y entorno de servicio

> Parte del informe de estado del arte (2026-11-03). Convenciones: `w` = ancho de línea (0.58), `h` = altura de capa (0.16), `s` = separación entre líneas. Ángulos de voladizo desde la vertical. Etiquetas de evidencia en `evidencia.md`. Lo marcado [I] es inferencia, no medición.

Las fichas de marcas distintas no se comparan con rigor: mezclan ISO, ASTM y GB/T, moldeado e impreso, y colores. Sedlák halló diferencias reales entre fabricantes del mismo material ([PMC10146359](https://pmc.ncbi.nlm.nih.gov/articles/PMC10146359/)) leído.

| Material | HDT 0.45 / 1.8 MPa | Tracción XY / Z MPa | Módulo MPa | Impacto | Fuente y método |
|---|---|---|---|---|---|
| eSUN PLA+ feb. 2026 | 53.78 °C / s.d. | 70.37 / 36.36 | Flexión 3259 XY, 2874 Z | Izod 7.27 XY, 2.22 Z kJ/m² | [TDS](https://www.esun3d.com/media/esun/catalog/certification/product/PLA_3KG1.75MM/PLA_-TDS-en.pdf), GB/T 1634, 1040, 9341, 1843, leído |
| eSUN PLA+ tabla general | 52 °C / s.d. | 65 / s.d. | Flexión 2102 | Izod 8.5 | [Tabla eSUN](https://cdn.shopify.com/s/files/1/1745/6181/files/eSUN_3D_Printing_Filament_Datasheet.pdf), método no indicado, leído |
| eSUN PLA | 56 °C / s.d. | 65 / s.d. | Flexión 3600 | Izod 4 | Tabla eSUN |
| eSUN PETG | 64 °C / s.d. | 49 / s.d. | Flexión 1170 | Izod 7.6 | Tabla eSUN |
| Prusament PETG V0 | 74 / 68 °C | 39 ± 2; entre capas 16.4 ± 1.3 | Tracción 1700 | Charpy 23 ± 1 | [TDS](https://cdn.shopify.com/s/files/1/1745/6181/files/prusament-petg-v0-technical-data-sheet.pdf), ISO 75, 527, 179-1, leído |
| eSUN ABS+ | 73 °C / s.d. | 40 / s.d. | Flexión 2443 | Izod 42 | Tabla eSUN |
| Bambu PETG-CF | 74 / 68 °C | 59 ± 4 / 38 ± 3 | Tracción 2460 XY, 1340 Z | 15.7 XY, 10.7 Z | [TDS](https://cdn.shopify.com/s/files/1/0380/5149/files/Bambu_PETG-CF_Technical_Data_Sheet.pdf), ISO 75, 527, 179, leído |
| UltiMaker TPU 95A | 50.3 °C a 0.455 MPa; Vicat 115.7 °C | Rotura 23.7 XY, 37.9 YZ, 6.4 Z | 67 XY, 56 Z | Alargamiento >560 % XY, 82 % Z | [TDS](https://um-support-files.ultimaker.com/materials/2.85mm/tds/TPU-95A/TDS-TPU95A-V2.01-250915.pdf), ISO 75-2/B, 306, ASTM D3039, leído |
| Spectrum PC/ABS FR V0 | s.d. / 90 °C; Vicat 104 °C | Fluencia 60 | 2850 | Izod entallado 35 | [TDS](https://spectrumfilaments.com/wp-content/uploads/2024/02/en_tds_spectrum_pc_abs_fr_v0.pdf), ISO 75-2/A, 306, 527, 180, leído |
| HP MJF PA12 | 173 / 121 °C o 175 / 95 °C | 30 o 48-49, en conflicto | 2800 XY | s.d. | [HLH](https://hlhrapid.com/wp-content/uploads/2022/06/HP-MJF-PA12-Spec-Sheet.pdf), [Weerg](https://weerg.com/hubfs/Datasheets/Datasheets%202024/ENG/EN_NylonPA12.pdf), vía buscador |
| Formlabs Tough 2000 V1 | 63 / 53 °C | 46 | 2200 | Alargamiento 48 % | [Formlabs](https://formlabs.com/support/Using-Tough-2000-Resin-V1/), vía buscador |
| Formlabs Tough 2000 V2 | 70 °C, carga no indicada | 40.4 | 1800 | Alargamiento 79 % | [Formlabs](https://formlabs.com/products/tough-2000-resin/), vía buscador |

La comparación más limpia es de un solo método, misma impresora y una sola marca ([CNC Kitchen](https://cnckitchen.com/blog/comparing-pla-petg-amp-asa-feat-prusament)) leído, Prusament en MK3S: gancho plano PLA 73 kg, PETG 55, ASA 57; de pie 40, 25 y 17 kg; módulo de flexión 3300, 1900 y 2300 MPa; Izod entallado 5, 8.6 y 18 kJ/m²; cede o falla a 60/~65, 80/~85 y 110/120 °C. Por eso "PLA es débil" y "PETG es más fuerte" son falsos en estática: PLA pierde por calor, fragilidad y fluencia, y PETG gana en tenacidad. "PLA+ resiste más calor" tampoco se sostiene, con HDT 52 frente a 56 °C en la [tabla eSUN](https://cdn.shopify.com/s/files/1/1745/6181/files/eSUN_3D_Printing_Filament_Datasheet.pdf). La tabla Bambu da HDT a 0.45 MPa de PLA 57, PETG 69, ABS 87, ASA 100 y PC 117 °C ([guía](https://cdn1.bambulab.com/filament/a5e185aed14e6/filament-guide-en-4.pdf)) [V] VENDOR. eSUN ABS+ con 73 °C casi empata a PETG V0, así que "auto caliente: ABS" es menos seguro de lo que se repite y conviene un ensayo de gancho en horno [I]. La tabla eSUN trae anomalías (ePC copia a ePA; eASA con HDT 54 °C; PETG con boquilla 190-220 °C), así que sus valores van con cautela.

| Requisito [I] | Con lo que hay hoy | Si hay que comprar o mejorar | Encargar fuera |
|---|---|---|---|
| Interior, frío, rígido, carga corta | PLA+ | | |
| Interior, golpes o clips | PETG | | |
| Carga sostenida a temperatura ambiente | PETG, esfuerzo bajo y margen amplio | PA12-CF con hotend metálico | SLS o MJF PA12 |
| Hasta ~60 °C | PETG; probar antes | ASA | |
| Auto al sol, soporte mecánico | Nada es seguro; ABS+ solo tras probarlo | ASA o PC con cerramiento y hotend metálico | MJF PA12 |
| Exterior con sol | PETG oscuro, provisional | ASA | |
| Humedad o agua | PETG o ABS+, no PLA+ | PP | MJF PA12 |
| Alcohol isopropílico | PETG o ABS+ con margen | PP | |
| Acetona | Ninguno | PP | |
| Combustibles y aceites | Sin datos; ensayar | | Pieza comercial |
| Roce, buje o engranaje liviano | PETG, sin depender de él | iglidur i180 o i150 | |
| Flexible | TPU 95A | | MJF TPU |
| Contacto con alimentos | Evitar; solo seco, breve y con recubrimiento | Filamento con informe EU 10/2011 y boquilla de acero inoxidable | |
| Envolvente con red eléctrica | Ninguno de los cuatro rígidos | PETG V0 (230 ± 10 °C, cabe en el hotend de serie) | Envolvente comercial certificada |
| Rigidez máxima en XY | PETG-CF con boquilla endurecida | PA-CF | |
| Carga sobre personas, presión, frenos | No imprimir | No imprimir | Pieza certificada |

Orden sugerido [I]: seguridad primero, después temperatura, UV y químicos como filtros duros, y al final rigidez e impacto, que el diseño compensa.

| Tamaño y warp [I], estimación sin medición | Sin cerramiento | Con cerramiento simple | Riesgo y notas |
|---|---|---|---|
| PLA+ | Toda la cama | No usar cerrado | Bajo; el calor atrapado perjudica |
| PETG | Toda la cama, borde en piezas largas | No hace falta | Bajo a medio; 235-240 °C, poco margen al techo |
| PETG-CF | Toda la cama | Ayuda algo | Bajo en warp; boquilla endurecida; rango Bambu desde 240 °C, en el borde del hotend |
| ABS+ | ~60-80 mm de lado, con borde | ~120-150 mm | Alto; sobre ~150 mm, despegue o grietas; 235-240 °C, cama 100 °C |
| TPU 95A | Toda la cama | No hace falta | Mínimo; 15-25 mm/s, retracción casi nula; evitar 85A y 90A |

La ficha de eSUN ABS Odorless dice que la contracción "is large" y pide "a closed chamber" ([TDS](https://cdn.shopify.com/s/files/1/1339/4265/files/eSUN_ABS_Odorless_Filament_TDS_V4.0.pdf)) leído. TPU 95A es viable en Bowden a 15-25 mm/s, y 85A y 90A casi siempre fallan por pandeo ([Filament Base](https://filamentbase.pages.dev/guides/sunlu-tpu-ender-3-v2.html)) vía buscador. PETG-CF con boquilla de latón es un problema activo, con relatos de boquilla de 0.4 abierta a 0.8 tras 1 kg o menos, sin ensayo controlado ([foro Bambu](https://forum.bambulab.com/t/petg-cf-will-it-wear-out-my-nozzle/216722)) vía buscador; medir con cubo de pared simple y pasar a boquilla endurecida [I]. La mejora de mayor impacto es hotend metálico más boquilla endurecida [I]. Con ABS en marco abierto también hay emisiones: un cerramiento ventilado a medida redujo partículas más de 99 % ([CDC](https://stacks.cdc.gov/view/cdc/172384/cdc_172384_DS1.pdf)) vía buscador, y hay que purgar los gases fuera del espacio habitable [I].

Exterior: con 100 h de lámpara de 125 W, 100 h de condensación a 55 °C y 100 % HR, y 98 días de intemperie bajo cubierta, en ISO 527-2 probeta 1BA, PLA cayó hasta −22.9 y −27.9 % en condensación (−2.3 % en otra marca), PETG no bajó de su referencia, ASA varió −4.3 a +3.1 % y ABS perdió hasta −6.9 % ([Sedlák 2023](https://pmc.ncbi.nlm.nih.gov/articles/PMC10146359/)) leído. Ninguna cifra justifica vida útil al sol directo [I]. La retención tras 7 días a 22 °C, ASTM D638 Tipo V, probetas verticales, n=3, es la siguiente ([Kaptan 2025](https://pmc.ncbi.nlm.nih.gov/articles/PMC12196949/)) leído; el artículo tiene incoherencias internas y usó una marca por material.

| Material | IPA 99 %, tracción / impacto | Acetona 99.5 %, tracción / impacto | Agua, tracción |
|---|---|---|---|
| PLA | 60-70 % / 55-60 % | ~0 % / ~5 % | ~100 % |
| PETG | ~85 % / ~64 % | ~30 % | >97 % |
| ABS | 82 % / 78 % | ~20 % / ~15 % | ~99 % |
| ASA | ~90 % / ~80 % | 30 % / 30 % | 100 % |
| PC | ~90 % / ~85 % | 25 % / 20 % | ≥95 % |
| PA | 80-85 % | ~40 % | ~95 % |
| PP | >95 % | 93-94 % | ~100 % |

No hay ensayos controlados de gasolina, diésel, aceite, agua salada ni lejía, ni de estrés químico bajo carga. Para red eléctrica, un UL94 de filamento vale para un espesor y unas condiciones y no convierte la pieza en envolvente certificada: Spectrum PC/ABS FR da V-0 a 1.5 y 3.0 mm ([TDS](https://spectrumfilaments.com/wp-content/uploads/2024/02/en_tds_spectrum_pc_abs_fr_v0.pdf)) leído, y Prusament PETG V0 clase V0 según IEC 60695-11-10 sin espesor en la TDS leída ([producto](https://www.prusa3d.com/product/prusament-petg-v0/)) vía buscador. Ninguno de los filamentos actuales debe ser la barrera única de seguridad, y PETG-CF lleva fibra de conductividad no declarada [I]. Usos prohibidos propuestos [I]: cargas sobre personas, izaje, frenos, dirección y retención en vehículos, recipientes a presión, cascos y protección, y barreras únicas de seguridad eléctrica. La pieza impresa es un consumible: revisar grietas blancas, separación de capas y flecha a los 3 y 12 meses en exterior [I]. No hay datos de vida útil en años.
