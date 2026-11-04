---
name: diseno-impresion-3d
description: Diseñar, modelar, revisar o corregir piezas funcionales para imprimir en 3D (FDM en la Ender-3 V2 de Daniel, con resina, SLS y MJF como comparación), sobre todo al modelar con el MCP de ScanRuler - orientación por carga, material, paredes por ancho de línea, voladizos, puentes, agujeros en gota, holguras, insertos térmicos, tornillos, tuercas, roscas `print45`, snap-fits, bisagras, partir piezas, reparar una pieza rota desde un escaneo y revisar un STL o 3MF antes de imprimir. Usar SIEMPRE antes del primer feature de cualquier pieza que se va a imprimir, aunque el pedido no mencione la impresión (soporte, carcasa, clip, adaptador, repuesto, tapa, gancho), y al preguntar por qué falló o se rompió una impresión. Para medir un escaneo sin imprimir nada basta `guide_read` de ScanRuler.
---

# Diseño de piezas funcionales para impresión 3D

**Orientar primero, calibrar siempre.** El orden de decisiones vale más que cualquier tabla: orientar la carga dentro del
plano de capa, dar espesor de pared en milímetros y medir una probeta propia. Casi todo lo específico de boquilla 0.5 es
inferencia: ningún valor publicado se midió en esta máquina. Las reglas son punto de partida y `references/calibracion.md`
las reemplaza con mediciones reales.

ScanRuler no revisa imprimibilidad: su mapa de espesor mide escaneos, no sólidos. Eso lo hace el script.

```bash
R=~/.claude/skills/diseno-impresion-3d/scripts/revisar_impresion.py
$R pieza.3mf                                    # todo: islas, puentes, voladizos, paredes, rendijas, láminas, base
$R pieza.stl --abajo 0,0,1                      # la cara +Z contra la cama (pieza en pose de ensamble)
$R pieza.stl --orientaciones --carga 0,1,0 --carga 1,0,0   # compara orientaciones; una --carga por tramo traccionado
$R pieza.stl --capa 0.11 --linea 0.58 --json    # otro perfil
```

Sale con código 1 si hay FALLA. Necesita `uv`. Sus umbrales son los de este archivo. `--carga` es la dirección de la
**tracción**, no de la fuerza: en flexión corre a lo largo de la fibra exterior, así que un gancho lleva una por tramo.

## La máquina

Creality Ender-3 V2: Bowden, marco abierto, Klipper por CB1 (`print_host = cb1`), PrusaSlicer con Arachne. Cama de
230 × 225 × 250 mm según el perfil; la cifra pública es 220 × 220, así que no llenar la cama sin confirmar.

| Dato | Valor | | Dato | Valor |
|------|-------|-|------|-------|
| Boquilla | 0.5 (hay perfiles 0.4, 0.6, 0.8) | | `min_bead_width` | 80 % = 0.40 mm |
| Línea `w` | 0.58 | | `min_feature_size` | 20 % = 0.10 mm |
| Capa `h` / primera | 0.16 / 0.20 | | `slice_closing_radius` | 0.049 mm |
| Perímetros | 3 | | Compensación XY y pata | 0 |
| Filamentos | PETG, PLA+, eSUN ABS+, TPU, PETG-CF | | Hotend | techo ~240 °C si lleva PTFE |

Si cambia el perfil, todo se recalcula: pared de n líneas = `w + (n−1)·s`, con `s = w − h(1 − π/4)`.

## Flujo

1. **Declarar la función.** Qué hace, dirección y tamaño de la carga, si es sostenida, temperatura, ambiente, ciclos, qué
   ajusta con qué y cuántas piezas. Sin carga declarada no se puede orientar. Lo que falte se asume y se dice en el chat, sin
   frenar el trabajo; las dudas con lugar van con `reverse_note_add` cuando ya exista un cuerpo donde fijarlas.
2. **Filtrar proceso y material.** Primero seguridad, luego temperatura, UV y químicos; rigidez al final, porque el diseño
   la compensa. Ver tabla abajo y `references/materiales.md`.
3. **Orientar por el camino de carga, antes de dibujar.** La tracción cruza capas a la mitad de la resistencia, y la
   tenacidad cae más. Avisar si la tracción principal pasa de 30° respecto al plano de capa. Con dos direcciones, partir la
   pieza antes que inclinarla.
4. **Parámetros primero** en ScanRuler: los que la pieza use de `w`, `h`, `h1`, `s`, `n_wall`, `wall`, `clr`, más los del
   diseño. Comentarios fieles al perfil. Antes del primer feature: `references/scanruler.md`, `guide_read { topic: "model" }`
   y aparte su sección `2. Building`, que la lectura completa no trae.
5. **Modelar macizo y tallar.** Partir de un bloque; el relleno lo pone el slicer. Con 3 perímetros, toda pared bajo 3.31 mm
   sale sólida. Las reglas rápidas aplican desde el primer croquis.
6. **Resolver uniones con herraje real.** Tabla rápida abajo y `references/uniones.md`.
7. **Calcular si hay carga sostenida** o si la falla molesta: `references/mecanica.md`, "Cálculo rápido", que trae el ejemplo
   resuelto de un gancho. Sobre la sección de paredes, sin contar relleno. De ahí salen los perímetros que hay que pedir.
8. **Revisar, en este orden:**
   1. `reverse_build`: `failed` debe venir vacío. **Es el único que lo dice**: un feature fallido responde `ok` al cambiar un
      parámetro, `reverse_body_check` da `ok` y el archivo se exporta sin él.
   2. `reverse_body_check { roundTrip: true }`.
   3. `reverse_body_clearance` en cada pareja que ajusta.
   4. `reverse_export_stl { format: "3mf" }` y el script. Corregir toda FALLA. Cada AVISO se corrige o se justifica por escrito.
9. **Entregar** con el informe de abajo. Lo que depende de una holgura se imprime primero como probeta: el rasgo crítico
   recortado (`cutPlane` en una copia, o corte en el slicer) en la misma orientación. Si la pieza lleva carga, proponer una
   prueba: colgar el doble de la carga de uso y medir a las 24 h y a los 7 días.

## Material en una mirada

| Necesidad | Hoy | Falta para hacerlo bien |
|-----------|-----|-------------------------|
| Interior, rígido, carga corta | PLA+ | |
| Interior, golpes, clips | PETG | |
| Hasta ~60 °C | PETG, probar antes | ASA |
| Sol y exterior | PETG oscuro, provisional | ASA |
| Auto al sol | Nada seguro; ABS+ solo tras probarlo | ASA o PC con cerramiento y hotend metálico |
| Carga sostenida | PETG con esfuerzo bajo | PA12-CF, o MJF por encargo |
| Flexible | TPU 95A a 15-25 mm/s; 85A y 90A pandean en Bowden | |
| Rigidez máxima en XY | PETG-CF con boquilla endurecida | No mejora Z; desgasta el latón |

- **Falso:** "PLA es débil", "PETG es más fuerte", "PLA+ aguanta más calor". PLA es más fuerte y rígido; pierde por calor,
  fragilidad y fluencia.
- **ABS+ en marco abierto:** riesgo alto sobre unos 60-80 mm de lado (estimación). Su HDT casi empata al PETG.
- **Carga sostenida:** al menos 20 °C bajo la HDT a 0.45 MPa.
- **No imprimir:** cargas sobre personas, izaje, frenos, dirección, recipientes a presión, protección personal, ni como
  única barrera de seguridad eléctrica. Red eléctrica: ningún filamento actual sirve. Decirlo y parar.
- **Si al soltarse puede caer sobre alguien** cuenta como posible lesión, no como falla inofensiva: decirlo y preguntar dónde
  va montada.

## Reglas rápidas

Ángulos **desde la vertical**: 0° es pared y 90° es techo plano.

| Rasgo | Regla en este perfil |
|-------|----------------------|
| Pared | Espesores limpios: 1.13, 1.67, 2.22, 2.76, 3.31. Bajo 1.13 avisa. Carga: 3-4 líneas o más |
| Rasgo fino | Bajo 0.10 desaparece. Entre 0.10 y 0.40 **sale a 0.40**, más grueso que el CAD y sin aviso. Funcional: 2.0 o más |
| Voladizo | Hasta 45-50°. Sobre 50° solo tras torre de prueba. Sobre 60°, soporte o rediseño |
| Puente | Bajo 5 en cara que importa, 10-15 oculto, sobre 20 partir. Recto y con dos apoyos: un voladizo con un solo apoyo no es puente |
| Agujero vertical | +0.2 de Ø bajo Ø10, en CAD. Nunca escalar la pieza: el error es casi fijo, no un porcentaje |
| Agujero horizontal | Gota a 45° sobre unos Ø5 o si un eje debe ajustar. Un M3 no la necesita |
| Base | Chaflán 0.5 × 45° en bordes de cama que ajustan o se ven. Nunca filete hacia la cama |
| Esquina vertical | Radio 0.5 o más; 1 o más a fatiga. Raíz de viga o tab: 0.5 × espesor o más |
| Unión de brazos | Chaflán grande o transición ancha en la raíz. Lo grueso casi no cuesta: por dentro es relleno |
| Texto | Relieve de 0.48 (3 capas), trazo de 1.13 o más, en paredes laterales |
| Alturas | Capas en `0.20 + k·0.16`. Bolsillos en múltiplos de 0.16 entre capas |
| Largo sobre la cama | El largo aumenta el warping; la altura y el espesor lo reducen. En ABS limitar el largo, no el espesor |

Soportes: evitarlos con orientación, chaflanes o partiendo la pieza; se aceptan con razón escrita y fuera de caras
funcionales. Modelados: separación de 1 capa en Z (0.16 o 0.32) y cerca de 0.5 en XY.

## Uniones y ajustes

| Tornillo | M2 | M2.5 | M3 | M4 | M5 | M6 | M8 |
|----------|----|------|----|----|----|----|----|
| Pasante libre | 2.5 | 3.0 | 3.5 | 4.5 | 5.5 | 6.5 | 8.5 |
| Tuerca, entre caras | 4.3 | 5.3 | 5.8 | 7.3 | 8.3 | 10.3 | 13.3 |
| Tuerca, profundidad | 2.08 | 2.40 | 2.88 | 3.68 | 5.12 | 5.60 | 7.20 |

| Inserto Ruthex o CNC Kitchen | M2 | M3 | M4 | M5 | M6 |
|------------------------------|----|----|----|----|----|
| Agujero CAD inicial | 3.4 | 4.2 | 5.8 | 6.6 | 8.2 |
| Profundidad ciega | 5.0 | 6.7 | 9.1 | 10.5 | 13.7 |
| Diámetro del boss | 6.2 | 7.8 | 10.5 | 12.3 | 15.3 |

| Ajuste, diametral sobre nominal, CAD | Boquilla 0.5 |
|--------------------------------------|--------------|
| Metal a presión en impreso, Ø10-30 | Nominal; probeta −0.1 a +0.2 |
| Impreso en impreso, prensa | −0.1 a −0.2 |
| Empuje a mano | +0.15 a +0.25 |
| Deslizante sin juego visible | +0.3 a +0.4 |
| Giro libre | +0.4 a +0.7, PETG arriba del rango |
| Print-in-place, **por lado** | 0.35-0.45 |

- **Cabezas, arandelas, asientos y fijación a una pared:** `references/uniones.md`, primera sección.
- **Por defecto, inserto** si hay reensamble o par: M3 aguanta unos 3-3.5 N·m contra 1 N·m del tornillo directo.
- **Rosca directa:** piloto `0.8 d + 0.25` (M3: 2.65), boss 2.5 d, enganche 2.5 d, eje paralelo a Z. Eje horizontal: boss
  3 d y piloto +0.1, porque abre capas. Máximo M3 0.5-0.6 N·m y pocos reensambles. Un pasante queda como diga la orientación.
- **Tuerca:** la carga hacia el material. En PETG, el bolsillo inferior aguantó 166 kg y el lateral 86 kg. Dejar 2 × alto
  de tuerca detrás y 3 líneas al lado.
- **Apriete:** menos de 15-20 MPa bajo la arandela, con `F = T/(0.2·D)`. El plástico fluye: manguito metálico si debe durar.
- **Rosca impresa:** nada bajo M8. Plástico con plástico, `print45`; con metal, inserto o tuerca.
- **Snap-fit:** ninguno con viga en Z. Viga en el plano XY, `L ≥ 10 h`, ancho ≥ 5, filete de raíz ≥ 0.5 h, sin carga en
  reposo. Deflexión `y = 0.67 ε L²/h`, con ε repetida: PETG 2.1 %, ABS 1.7 %, PLA 1.3 %.
- **Bisagra viva:** no portar a PETG, PLA ni ABS salvo pocos ciclos. Pasador o pieza aparte.
- **Reparación:** `mesh_trim` corta el trozo con la fractura escaneada. Ver `references/scanruler.md` §5.

## Trampas

- **Convención de ángulos.** PrusaSlicer y Orca miden desde la horizontal. Muchas guías y la regla original de Slant dan
  "45°" sin decir desde dónde; escrita "respecto al eje vertical, 45° o más" permite un techo plano.
- **Pata de elefante: una sola vía.** Chaflán o compensación del slicer, no ambos.
- **Valores en mm de guías publicadas** suponen boquilla 0.4. Derivar de `w` y `h`.
- **Reglas de granja.** Slant optimiza costo, expulsión y un perfil que el cliente no controla. Aquí sí se controla el
  slicer. Rechazadas como reglas generales: "cero soportes" y "nada estético contra la cama".
- **Comba de un puente:** el slicer lo imprime igual aunque vaya a colgar. Decide por anclajes, no por largo.
- **Micro-ranuras (0.1-0.2 mm):** prometedoras y sin datos independientes. Si las paredes no se funden, debilitan.
- **Copiar una pieza inyectada.** Sus paredes de 1-1.5 mm y sus nervios existen por el molde y salen frágiles en FDM. Tabla
  de conversión en `references/agente.md`.
- **El STL de un ensamble sale en pose de ensamble.** Revisarlo con `--abajo` o marcará islas falsas.
- **ScanRuler:** la pestaña puede tener otra pieza u otra sesión: nunca `discard`. `reverse_body_clearance` necesita pestaña.
  Los nombres de parámetro no distinguen mayúsculas: con `w` y `h` definidos, `W` y `H` se rechazan.

## Informe de entrega

1. Pieza, material y orientación, con la razón (carga frente a capas).
2. Ajustes de slicer que el diseño necesita: perímetros, relleno, soportes.
3. Cálculo: esfuerzo, admisible y margen, si hay carga.
4. Revisión: `reverse_build` sin fallidos, script con FALLA en 0, cada AVISO corregido o justificado.
5. Supuestos: carga, temperatura, montaje y todo valor sin calibrar.
6. Qué imprimir primero como probeta, qué medir y la prueba de carga.
7. Archivos: `.scanruler`, STEP, 3MF.

## Mapa

| Tarea | Leer |
|-------|------|
| Recetas en ScanRuler, `mesh-tools`, motor headless | `references/scanruler.md` |
| Paredes, voladizos, agujeros, base, warping | `references/geometria.md` |
| Insertos, tornillos, tuercas, roscas, snap-fits, bisagras, engranajes, rodamientos, partir | `references/uniones.md` |
| Elegir material, calor, UV, químicos | `references/materiales.md` |
| Calcular resistencia, fatiga, fluencia, factores | `references/mecanica.md` |
| Lista de 24 reglas, escaneo, inyección a FDM, validación | `references/agente.md` |
| De dónde sale cada cifra, Slant regla por regla, otros procesos | `references/evidencia.md`, `references/videos.md` |
| Valores medidos en esta máquina | `references/calibracion.md` |

## Ciclo de aprendizaje

Al cerrar una pieza:

1. ¿Se midió algo impreso? Anotarlo en `references/calibracion.md` y, si contradice una regla, corregirla aquí.
2. ¿Falló una receta de ScanRuler, o la forma correcta era otra? Corregir `references/scanruler.md`.
3. ¿El script dio un falso positivo o dejó pasar un fallo real? Agregar el caso a `scripts/test_revisar_impresion.py`.
