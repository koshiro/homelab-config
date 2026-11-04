# Recetas de ScanRuler para piezas impresas

Esto no reemplaza `guide_read`: el orden de construcción, los fallos del kernel y la forma de cada herramienta están en
las guías `model` y `model-reference`. Aquí va solo lo específico de imprimir.

**Estado:** las recetas de §3 se construyeron en el motor headless de ScanRuler 0.9.4 (scanruler-mcp 0.6.1) el
2026-11-03, con sólido cerrado y STEP de ida y vuelta limpio. Las de §5 (`mesh-tools`) necesitan escaneo y pestaña, y
**no se ejecutaron**: salen del README y del esquema del plugin. Fuentes: `plugins/reverse` y `plugins/mesh-tools` de
`github.com/CNCKitchen/scanruler`, commit `5c1f2f9`.

## 1. Antes del primer feature

1. `scanruler_status`, luego `session_state`. La pestaña puede tener otra pieza y otra sesión conectada
   (`server.role: "relay"`). Nunca `discard`: guardar primero con `saveTo`.
2. Elegir **orientación de impresión antes de dibujar** (SKILL.md): decide qué rasgos son posibles.
3. Parámetros de impresora en el primer `reverse_parameter_add`, junto con los del diseño. Las expresiones aceptan
   aritmética, otros parámetros y `pi`:

```json
{ "parameters": [
  { "name": "w",      "expression": "0.58", "comment": "ancho de línea" },
  { "name": "h",      "expression": "0.16", "comment": "altura de capa" },
  { "name": "h1",     "expression": "0.20", "comment": "primera capa; alturas desde la cama: h1 + k*h" },
  { "name": "s",      "expression": "w - h*(1 - pi/4)", "comment": "paso entre líneas" },
  { "name": "n_wall", "expression": "4", "kind": "integer", "comment": "líneas del espesor de pared de diseño, no perímetros del slicer" },
  { "name": "wall",   "expression": "w + (n_wall - 1)*s", "comment": "pared que el slicer llena sin huecos" },
  { "name": "clr",    "expression": "0.3", "comment": "holgura por lado; calibrar con cupón" }
] }
```

El comentario debe decir la verdad del perfil. En `boton-ble`, `wall = 1.2` decía "3 perímetros de 0.4" con línea de
0.58: eso son 2 líneas, no 3.

Agregar solo los que la pieza use: el resto queda con `drivesNothing`. Los nombres no distinguen mayúsculas, así que con `w`
y `h` definidos usar `ancho` y `alto`, no `W` y `H`.

El aviso `no plan set` del primer croquis es para escaneos (`reverse_plan_set`): sin escaneo se ignora.

Un número se ata a un parámetro con `exprs` (`{ "extent.from": "cb_depth + h" }`) o con una cota en el croquis
(`{ "kind": "diameter", "entity": 1, "expr": "d_pin + 2*clr" }`). Cambiar `clr` con `reverse_parameter_set` reconstruye
todo.

## 2. Pose: Z es la dirección de impresión

- Pieza suelta: modelar con z = 0 en la cama. El archivo sale listo para el slicer.
- Ensamble: conservar la pose de ensamble para medir holguras, y anotar la cara de cama de cada cuerpo. Se revisa con
  `--abajo` (la tapa de `boton-ble` se imprimió volteada: `--abajo 0,0,1`).
- Planos verticales con `up: "z"`: v siempre sube y u = up × normal, así que un pico en +v apunta a +Z en cualquier plano.

## 3. Recetas

### Chaflán inferior

Un `where` se evalúa de nuevo en cada build: sobrevive a cambios del contorno. Toma también los agujeros que tocan la cama.

```json
{ "kind": "chamfer", "name": "Chaflan cama", "body": "Base", "distance": 0.5,
  "edges": [{ "box": { "min": [-500, -500, -0.01], "max": [500, 500, 0.01] }, "sharp": true }] }
```

Va al final, con los demás redondeos. Leer `picked`.

Borde superior: `between` con una sola normal toma también los cilindros de eje Z, así que se acota con un `box` abierto
hacia arriba, que sobrevive a cambios de altura:

```json
{ "kind": "chamfer", "name": "Chaflan tope", "body": "Base", "distance": 1,
  "edges": [{ "between": [[0, 0, 1]], "sharp": true, "box": { "min": [-500, -500, 10], "max": [500, 500, 500] } }] }
```

Si un agujero queda cerca del borde, el chaflán puede fallar **sin avisar** al cambiar un parámetro: ver §4.

### Agujero horizontal en gota

Arco de 270° más dos rectas tangentes a 45°. Las coordenadas iniciales salen de las fórmulas de abajo, y las cotas atan
la forma a los parámetros. Plano vertical con `up: "z"`, centro [30, 10], `d_pas` 4.5, `y_s` y `z_c` del diseño:

```json
{ "kind": "sketch", "name": "Gota", "plane": { "kind": "world", "axis": "x", "up": "z" },
  "sketch": { "entities": [
    { "id": 1, "kind": "arc",  "c": [30, 10], "r": 2.25, "start": 2.35619449, "sweep": 4.71238898 },
    { "id": 2, "kind": "line", "a": [31.59099, 11.59099], "b": [30, 13.18198] },
    { "id": 3, "kind": "line", "a": [30, 13.18198], "b": [28.40901, 11.59099] }
  ], "constraints": [
    { "kind": "radius", "entity": 1, "expr": "d_pas/2" },
    { "kind": "tangent", "a": 1, "b": 2 },
    { "kind": "tangent", "a": 1, "b": 3 },
    { "kind": "distance", "p": { "entity": 1, "at": "center" }, "q": { "datum": "zx" }, "expr": "y_s" },
    { "kind": "distance", "p": { "entity": 1, "at": "center" }, "q": { "datum": "xy" }, "expr": "z_c" },
    { "kind": "distance", "p": { "entity": 2, "at": "b" }, "q": { "datum": "zx" }, "expr": "y_s" },
    { "kind": "angle", "a": 2, "b": 3, "value": 90 }
  ] } }
```

Para varias gotas, repetir el bloque con otros ids: `patterns` tiene paso numérico y sus copias pierden las cotas.

- Tangencia en `(cu ± 0.7071 r, cv + 0.7071 r)`. Pico en `(cu, cv + 1.4142 r)`.
- Cortar con `{ "kind": "extrude", "sketchId": "Gota", "regions": "all", "op": "cut", "target": "Base", "extent": { "kind": "distance", "from": -1, "to": 13 } }`.
- Si el pico estorba, truncarlo con una recta horizontal en `cv + 1.1 r`.
- Un M3 horizontal no la necesita: es corto y el tornillo lo fuerza (Maker's Muse). Importa en ejes y agujeros grandes.

### Inserto térmico

`hole` trae la gama de CNC Kitchen. Da Ø y un fondo 1 mm más profundo que el inserto. La columna **pared** es la pared
mínima alrededor del agujero: `hole` no la comprueba, hay que dejarla al diseñar la torreta.

```json
{ "kind": "hole", "name": "Inserto M3", "body": "Base", "insert": "M3",
  "axis": { "kind": "point", "at": [20, 10, 20],
            "face": { "kind": "plane", "between": [[0, 0, 1]], "box": { "min": [-31, -21, 19.9], "max": [31, 21, 20.1] } } } }
```

| `insert` | Largo | Agujero | Pared mín. |
|----------|-------|---------|-----------|
| `M2` | 3.0 | 3.2 | 1.3 |
| `M2.5` | 4.0 | 4.0 | 1.6 |
| `M3` | 5.7 | 4.0 | 1.6 |
| `M3 short` | 3.0 | 4.0 | 1.6 |
| `M3 Voron` | 4.0 | 4.4 | 1.3 |
| `M4` | 8.1 | 5.6 | 2.1 |
| `M4 short` | 4.0 | 5.6 | 2.1 |
| `M5` | 9.5 | 6.4 | 2.6 |
| `M5 short` | 5.8 | 6.4 | 2.6 |
| `M6` | 12.7 | 8.0 | 3.3 |
| `M8` | 12.7 | 9.7 | 3.3 |
| `1/4"-20` | 12.7 | 8.0 | 3.3 |

**Ojo con el Ø4.0 del M3.** Es el valor de ficha. El ensayo posterior de CNC Kitchen (M3×5.7, PLA, casi 50 insertos) vio
rebaba severa hasta 4.0 y asiento correcto a **4.2**, con cerca de 90 % de la extracción máxima. Los agujeros salen chicos,
así que para el valor de `uniones.md` se usa `radius` y `depth` en vez de `insert`:

```json
{ "kind": "hole", "name": "Inserto M3", "body": "Base", "radius": 2.1, "depth": 6.7, "axis": { "kind": "point", "face": 5 } }
```

Otra marca: `radius` y `depth` desde su ficha.

### Rosca impresa

- `standard: "print45"`: flancos a 45°, profundidad 0.3 × paso, cresta y raíz planas de 1/5 del paso. Eje vertical, sin
  soportes. **Solo enrosca consigo misma.**
- Tamaños `"Ø3"` en adelante, con el paso que corta tan hondo como el ISO grueso: Ø6×1.75, Ø8×2.25, Ø10×2.75, Ø12×3,
  Ø16×3.5, Ø20×4.5. Conserva el diámetro menor ISO, así que el núcleo es igual de fuerte.
- `offset` es la holgura: mueve todas las caras hacia el material. Con boquilla 0.5 se buscan 0.3-0.4 por flanco en
  total, repartidos entre las dos piezas (0.15-0.2 en cada una). Se rechaza desde √2/8 del paso (0.177 × paso).
- Bajo unos Ø8 la rosca no tiene capas suficientes por paso: preferir inserto o tuerca (`uniones.md`).
- Las roscas van después de todo lo que toca el agujero, sobre un agujero sin chaflanes (guía `model`, §2 paso 10).

```json
{ "kind": "thread", "name": "Rosca", "body": "Base", "face": { "kind": "cylinder", "radius": 10 },
  "standard": "print45", "size": "Ø20", "offset": 0.2, "chamfer": true }
```

### Alojamiento para una pieza comprada

`offsetBody` hace una zona de exclusión con holgura uniforme, y `boolean` con `keep` corta sin perderla. Modelar la pieza
comprada a su tamaño real como cuerpo `new`. Sirve para placas, rodamientos, imanes o pilas.

```json
{ "kind": "offsetBody", "name": "Keepout", "body": "Comprada", "distance": 0.3, "exprs": { "distance": "clr" } }
{ "kind": "boolean", "name": "Alojamiento", "op": "cut", "body": "Caja", "tool": "Keepout", "keep": true }
```

Ocultar los auxiliares con `reverse_feature_update { feature, set: { visible: false } }`: salen de la exportación. Los
cantos convexos de `offsetBody` salen redondeados.

### Alojamiento de tuerca hexagonal

`fit: "circumscribed"` mide entre caras, como una llave. M3 con boquilla 0.5: 5.8 entre caras, radio 2.9, profundidad
2.88 (18 capas). Otros tamaños en `uniones.md`.

```json
{ "kind": "sketch", "name": "Tuerca sk", "plane": { "kind": "world", "axis": "z", "offset": 20 },
  "sketch": { "shapes": [{ "kind": "polygon", "center": [20, -10], "sides": 6, "radius": 2.9, "fit": "circumscribed", "fixed": true }] } }
```

### Membrana de sacrificio sobre un avellanado

Un agujero que sale de un avellanado hacia abajo deja un techo sin apoyo. El pasante empieza una capa más arriba: queda
una membrana de altura `h` que se perfora después. El revisor la avisa como `lámina fina`, y es lo esperado.

```json
{ "kind": "extrude", "name": "Avellanado corte", "sketchId": "Avellanado", "op": "cut",
  "extent": { "kind": "distance", "from": 0, "to": 3 }, "exprs": { "extent.to": "cb_depth" } }
{ "kind": "extrude", "name": "Paso corte", "sketchId": "Paso", "op": "cut",
  "extent": { "kind": "distance", "from": 3.16, "to": 25 }, "exprs": { "extent.from": "cb_depth + h" } }
```

### Micro-ranura de refuerzo

Una ranura de 0.2 mm obliga al slicer a poner paredes a cada lado, que se funden y dejan zona sólida. Es un corte
extruido normal, no necesita nada especial. Ancho mínimo 0.1 mm: el perfil de Daniel tiene `slice_closing_radius = 0.049`
y cierra lo que sea menor. El revisor la avisa como `rendija`.

- Alrededor de un agujero: disco cortado a unos 2 × el espesor de pared del agujero, para que las paredes de ambos lados
  se junten y quede sólido. Con 3 perímetros de este perfil son unos 3.3 mm.
- Si las paredes no se funden, queda una funda suelta alrededor de un núcleo y la pieza es **más débil**. Slant dice que
  da unas 3 veces la resistencia, sin datos publicados y sin probarlo con Arachne ni línea de 0.58: romper una muestra
  antes de confiar. Ver `videos.md`.

### Partir una pieza

Copiar y cortar por el mismo plano (los dos cortes usan `keep` opuesto):

```json
{ "kind": "moveBody", "name": "Mitad B", "bodies": ["Caja"], "translate": [0, 0, 0], "copy": true }
{ "kind": "cutPlane", "name": "Corte A", "body": "Caja", "plane": { "kind": "world", "axis": "x" }, "keep": 1 }
{ "kind": "cutPlane", "name": "Corte B", "body": "Mitad B", "plane": { "kind": "world", "axis": "x" }, "keep": -1 }
```

Agregar pasadores o cola de milano antes de separar. Un 3MF deja cada mitad como objeto propio.

## 4. Revisión antes de entregar

Además de los chequeos de la guía `model` §3:

1. `reverse_build`: `failed` debe venir vacío. Un `reverse_parameter_set` que deja un chaflán fallido responde `ok`,
   `reverse_body_check` y el STEP también, y el 3MF sale sin ese chaflán. Se reprodujo en la prueba del gancho.
2. `reverse_body_check { roundTrip: true }`: sólido cerrado, sin vacíos internos.
3. `reverse_body_clearance { body }` con cada pieza que toca: compara `gap` con la holgura buscada. Un `overlap` es
   interferencia, salvo en ajuste a presión. **Necesita pestaña.**
4. `reverse_export_stl { "format": "3mf", "path": "<carpeta>/pieza.3mf" }`. Salen los cuerpos visibles, cada uno como
   objeto. El `chord` por defecto de 0.02 mm sobra para FDM.
5. Correr el revisor (SKILL.md).

`thickness_measure` y `scan_draft` trabajan **sobre el escaneo**, no sobre sólidos. Una pieza modelada se revisa con el
script. Abrir el STL como escaneo para usar el mapa de espesor reemplaza la sesión: no hacerlo sobre una pestaña con
trabajo.

## 5. Con escaneo: `mesh-tools`

Necesitan escaneo y pestaña. Los comandos editan una copia de la malla, y cada uno es un paso del historial.

**Reparar una pieza rota, imprimir y pegar** (`Trim to scan`):

1. Escanear lo que queda. En `reverse`, modelar el trozo que falta con su forma nominal y unos milímetros de más hacia la
   fractura. Puede ser un poco mayor que la pieza.
2. `mesh_trim { body, offset: 0.15 }`: corta el cuerpo con la fractura escaneada. `offset` deja espacio para pegamento
   (0 corta justo en la rotura). `depth` (0.3 mm) define qué cuenta como rotura.
3. Leer la respuesta: volumen, cara de unión y distancia real a la pieza.
4. `mesh_export { part: "piece", format: "3mf", path }`. Sale en la pose de la pieza, no de impresión: elegir la
   orientación y revisar con `--abajo`.

**Pieza que se adapta a una superficie orgánica** (soporte, cuna, empuñadura):

1. Dejar solo la zona de contacto: `mesh_cut`, `mesh_mark` y `mesh_delete_marked`.
2. `mesh_offset { direction: "expand", distance: <holgura> }`. Mueve la superficie, no escala: un agujero se achica.
3. `mesh_shell { mode: "thicken", side: "out", thickness: <pared> }` convierte la superficie abierta en sólido.
4. `mesh_export { part: "edited", format: "3mf", path }` y revisar. El escaneo es referencia de la cara de contacto: lo
   demás se modela.

**Otros usos:**
- `mesh_offset { direction: "shrink" }`: corrige una impresión que salió gorda. Es para correcciones pequeñas frente a los
  rasgos. Con `region` mueve solo esa superficie.
- `mesh_shell { mode: "hollow" }`: ahuecar para resina. En FDM casi nunca hace falta, porque el relleno ya es hueco.
- `mesh_boolean { op, solids }`: une o resta cuerpos modelados de una malla cerrada.

## 6. Medir lo impreso

La pieza impresa vuelve a ScanRuler como escaneo, y el error se corrige en el CAD como parámetro:

1. `scan_open` de la pieza. `reverse_body_compare_in_deviation` si el modelo sigue abierto; si no,
   `deviation_open_reference` con el STEP y `deviation_align`.
2. `deviation_hotspots` da dónde y cuánto se desvió. Con calibre también vale.
3. Ajustar `clr` y similares con `reverse_parameter_set`, nunca escalando la pieza entera.
4. Promediar varias piezas: corregir con una sola también corrige su ruido.

La guía `scan-to-cad` clasifica una pieza FDM en tolerancia de 0.3-0.5 mm: es la T para comparar.

## 7. Motor headless

Corre modelado, parámetros, `reverse_body_check` y exportación sin navegador, en una sesión aislada.

```bash
# Una vez, en un clon de github.com/CNCKitchen/scanruler
npm ci --ignore-scripts && npm run build:engine
# Para arrancar el servidor
npx -y scanruler-mcp@latest --engine <clon>/dist-engine/engine.mjs --port 7399
```

No responden sin pestaña: `reverse_body_clearance`, `reverse_body_set`, `project_save`, `view_render`, ni las herramientas de
escaneo y malla. Sin `project_save` no hay `.scanruler`: guardar el JSON de llamadas, que reconstruye el modelo en una
pestaña. Sin `reverse_body_set`, el STEP nombra el cuerpo `Solid 1`.
