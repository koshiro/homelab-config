# LoRAs de personaje para Z-Image Turbo con un dataset sintético

Metodología para crear un personaje ficticio **con el mismo Z-Image Turbo**, elegir el set de entrenamiento entre esas
generaciones y entrenar una LoRA capaz de repetirlo **desnudo, con cualquier ropa y en cualquier situación**. Estudio
del 2026-10-05; lo marcado *(probar)* todavía no se ha probado en este cluster.

Requisito de partida: el personaje es **ficticio y adulto**. La edad va explícita en el bloque de identidad (25 años o
más) y nunca se usa el nombre de una persona real como atajo. Si no, la LoRA aprende un parecido real y lo reproduce
desnudo.

## Idea central

Una LoRA de personaje aprende lo que **se repite en todas las imágenes y no está en el caption**. Todo lo demás lo
asocia al texto que lo describe. Por eso:

1. **La identidad** (cara, cuerpo, marcas) tiene que ser idéntica en todo el set y **no** se describe en los captions:
   la carga el trigger.
2. **Lo variable** (ropa o desnudez, peinado si cambia, pose, lugar, luz, encuadre) tiene que variar de verdad y estar
   **siempre descrito** en el caption. Si todas las imágenes llevan jeans, la LoRA "es" alguien con jeans. Si ninguna
   está desnuda, al pedir desnudo vuelve el cuerpo por defecto del modelo, o aparece ropa del set ("clothing bleed").
3. **Nada variable puede quedar correlacionado**: si todos los desnudos son en un dormitorio, "desnudo" arrastra el
   dormitorio, y si todos los primeros planos tienen fondo de estudio, la cara arrastra el estudio.

Z-Image Turbo ayuda en la primera parte: la destilación (DMD + RL) colapsa la salida hacia la interpretación más
probable, así que un mismo bloque de identidad tiende a dar la misma cara. Pero la cara deriva al cambiar ángulo,
encuadre o escena, y en planos enteros la cara es chica y sale peor. El set se **selecciona**: no todo lo generado
sirve.

## Fase 1 — Diseñar el personaje (hoja de identidad)

Escribe un bloque fijo, en inglés y en el dialecto nativo del modelo (hechos visibles, sin adjetivos de valor, sin
"beautiful" ni meta-tags). Debe ser **distintivo**: si describes una cara genérica, Z-Image produce su cara por
defecto (belleza de stock, rasgos de Asia oriental si no declaras etnia), la LoRA aprende casi nada distinto del modelo
base y el personaje no se distingue de cualquier mujer generada sin LoRA.

Qué fijar:

| Dimensión | Ejemplo | Nota |
|---|---|---|
| Edad y origen | `a 29-year-old Argentine woman of Italian descent` | Edad numérica; la etnia siempre declarada |
| Geometría de la cara | `oval face with a slightly pointed chin, high cheekbones` | Rasgos concretos, no "pretty" |
| Ojos y cejas | `wide-set hazel-green eyes, thick straight dark eyebrows` | |
| Nariz y boca | `a straight nose with a small bump on the bridge, full lips` | Un rasgo "imperfecto" ancla la identidad |
| Piel y marcas | `light olive skin, faint freckles across the nose, a small dark mole on the left cheekbone` | Marcas simples y repetibles. **Evitar tatuajes complejos**: el modelo no los repite igual y la LoRA aprende ruido |
| Pelo | `shoulder-length wavy chestnut-brown hair with a center part` | Si es fijo, va a la identidad. Si quieres poder cambiarlo, ver Fase 3 |
| Cuerpo | `168 cm, slim athletic build, small natural breasts, narrow waist, toned legs` | Necesario para que el cuerpo desnudo sea coherente con el vestido |
| Cuerpo desnudo | vello púbico, pezones, cicatrices o marcas del torso | Decide y fija; si cambian entre imágenes, la LoRA no los aprende |

Bloque de ejemplo (~90 palabras, estable entre todas las generaciones):

```text
The woman is a 29-year-old Argentine woman of Italian descent with an oval face, a slightly pointed chin and high
cheekbones. She has wide-set hazel-green eyes, thick straight dark eyebrows, a straight nose with a small bump on the
bridge and full lips. Her skin is light olive with faint freckles across the nose and a small dark mole on her left
cheekbone. She has shoulder-length wavy chestnut-brown hair with a center part. She is 168 cm tall with a slim athletic
build, small natural breasts, a narrow waist and toned legs.
```

Antes de producir el set, haz un **casting**: el mismo bloque con 8 a 16 seeds y un encuadre neutro (retrato de frente,
luz suave). Elige la cara que te guste y **ajusta el texto** hasta que la mayoría de las seeds den esa cara. Con Turbo
la seed cambia la textura más que la composición: si las seeds dan caras distintas, falta precisión en el texto.
Guarda la imagen elegida como **referencia** (sirve para la curación por similitud, Fase 4).

## Fase 2 — Generar el set candidato

### Estructura del prompt

Orden canónico de Z-Image, con la identidad **copiada letra por letra** en cada prompt:

```text
[1 medio + encuadre]  A full-body smartphone photograph of a woman standing in a sunlit bedroom.
[2 identidad fija]    The woman is a 29-year-old Argentine woman ... toned legs.
[3 ropa / desnudez]   She is completely naked. / She wears a fitted mustard-yellow ribbed knit dress ...
[4 pose y gesto]      She stands with her weight on her right leg, hands on her hips, smiling slightly at the camera.
[5 entorno]           White linen curtains behind her on the left, an unmade bed in the background ...
[6 luz]               Soft morning daylight from a window on the left side of the frame.
[7 propiedades medio] Natural colors, visible skin texture, sharp focus on her face, slight phone-camera noise.
```

Por qué así:

- **Identidad temprana y constante.** El encoder (Qwen3-4B) tiene atención causal: lo que va antes no "ve" lo que va
  después. Con la identidad en la segunda frase, solo la primera puede re-contextualizarla, y la primera es corta. Lo
  variable va después, así que cambiarlo no altera la identidad. *(probar)* Hacer A/B con la identidad como primera
  frase y comparar la deriva de la cara.
- **La ropa se nombra con color, material y corte** (`mustard-yellow ribbed knit dress`, no `casual outfit`): el mismo
  texto irá al caption y le enseña a la LoRA que esa prenda viene del texto, no del personaje.
- **Desnudez en afirmativo** (`She is completely naked`, `topless, wearing only black cotton briefs`), no `no clothes`.
  Mencionar la ropa aunque sea negada la introduce.
- **Una sola persona por imagen.** Con varias personas, Turbo mezcla atributos (attribute binding más bajo que el modelo
  base) y la LoRA aprende caras ajenas. Las escenas con más gente se piden después, en inferencia.
- Sin pesos `(x:1.3)`, sin `masterpiece/8k`, sin metáforas: en ComfyUI los pesos llegan como texto literal.

### Matriz de variación (decorrelacionar)

Arma una tabla de 50 a 70 prompts candidatos cruzando estos ejes, de modo que ningún valor de un eje quede atado a uno
de otro (los desnudos van en planos enteros, medios y primeros planos, y en interiores y exteriores):

| Eje | Reparto objetivo en el set **final** (~30–40 imágenes) |
|---|---|
| Encuadre | 30 % primer plano (cara y hombros) · 35 % plano medio · 35 % cuerpo entero |
| Ángulo de la cara | frente, 3/4 a ambos lados, 2 perfiles, mirando arriba y abajo, 1 de espaldas |
| Expresión | neutra, sonrisa, risa, seria, pensativa, sorpresa, triste |
| Vestimenta | ~30 % desnuda · ~15 % ropa interior o traje de baño · ~55 % vestida, **ninguna prenda o color repetido más de 2 veces** (formal, deportiva, invierno, verano, pijama, uniforme...) |
| Escena | interior y exterior; casa, calle, playa, oficina, naturaleza, estudio liso (pocas: el estudio no enseña nada) |
| Luz | día natural, sol duro, atardecer, interior cálido, flash, noche con neón |
| Pose y acción | de pie, sentada, acostada, caminando, de espaldas, con objetos (taza, libro, bicicleta) |
| Formato | 832×1216, 1024×1024, 1216×832 (~1 MP, lados múltiplos de 16) |

Las imágenes desnudas en primer plano y plano medio importan: enseñan que el torso desnudo pertenece al mismo cuerpo que
la cara. Las de cuerpo entero desnudo fijan proporciones (altura, caderas, piernas) que la ropa oculta.

### Parámetros

Los del workflow habitual: CyberRealistic Z-Image Turbo v9, 8–9 pasos, CFG 1, `res_multistep` o `euler` +
`simple`, sin LoRAs (cualquier LoRA de estilo o de cuerpo contamina el set y queda horneada en el personaje). Para
cuerpos enteros, pasar un **FaceDetailer** (`face_yolov9c` ya está) con el **mismo bloque de identidad** en el prompt
del detailer y denoise bajo (0,3–0,45): sin eso la cara de un plano entero sale pequeña y genérica, y un detailer con
prompt genérico la reemplaza por otra cara.

Guardar con `filename_prefix` = `%date:yyyy-MM-dd%/lora-<personaje>/<eje>` para que el set quede junto en la galería.

## Fase 3 — Selección del set

Desde SmartGallery: una **colección por personaje** y las estrellas para marcar las candidatas.

Criterios de descarte:

- **Cara**: no es la misma persona que la referencia. Mejor medirlo que juzgarlo a ojo (ver Fase 4).
- **Cuerpo**: proporciones distintas al resto (busto, caderas o altura que cambian), marcas que faltan o migran (el lunar
  en la otra mejilla).
- **Defectos**: manos, dedos, anatomía genital deforme, piel plástica. La LoRA aprende también los defectos.
- **El prompt no se cumplió** en algo que irá al caption: corrige el caption o descarta la imagen.
- **Redundancia**: dos imágenes casi iguales aportan menos que una distinta.

Resultado: **30–40 imágenes** que respeten la matriz. Mejor 25 buenas que 40 con deriva.

**Peinado variable** *(opcional)*: si quieres poder pedir otros peinados, ~70 % del set lleva el peinado por defecto
(sin describirlo en el caption) y ~30 % otros peinados, **descritos** en el caption (`her hair is tied in a high
ponytail`). Con 100 % del mismo peinado, la LoRA lo fija y cuesta cambiarlo.

## Fase 4 — Curación por similitud facial *(probar)*

Un script con InsightFace (ArcFace `buffalo_l`) calcula, para cada candidata, la similitud coseno de su cara contra la
media de 3 a 5 referencias elegidas a mano. Orientativo: >0,6 es casi seguro la misma identidad y <0,45 se descarta.
Calibrar el umbral con el propio set. Corre en CPU y sirve en `k3s-node-1` (NumPy requiere x86-64-v2; los nodos 2 y 3
no lo tienen). Las imágenes de espaldas o de perfil extremo no tienen score fiable: se juzgan a ojo.

## Fase 5 — Captions

El caption **no es** el prompt de generación. Se obtiene de él así:

1. Reemplazar el bloque de identidad (y cualquier rasgo fijo mencionado en otro lado) por `<trigger>, a woman`.
2. Mantener todo lo variable: medio, encuadre, ropa o desnudez, peinado si se desvía, pose, expresión, entorno, luz.
3. **Corregir según la imagen, no según la intención.** Si pediste un vestido rojo y salió burdeo, el caption dice
   burdeo. Para revisar a escala, un VLM: [JoyCaption](https://huggingface.co/fancyfeast/llama-joycaption-beta-one-hf-llava)
   está hecho para captions de entrenamiento y no se niega con desnudos; Qwen-VL en el Ollama del cluster sirve para la
   parte vestida. El VLM **verifica y corrige**; el caption base sale del prompt.
4. Mismo dialecto que usarás al generar: frases factuales en inglés, sin meta-tags. Z-Image se usa con prosa, así que
   los captions en prosa enseñan la asociación en el mismo formato de la inferencia.

**Trigger**: una cadena rara que no colisione con palabras o nombres conocidos (`zk4rla`, no `Karla`). Qwen la parte en
sub-tokens sin problema. Acompañarla de la clase (`a woman`) ayuda a anclarla en lo que el modelo ya sabe.

Ejemplo, desnudo:

```text
A full-body smartphone photograph of zk4rla, a woman, standing completely naked in a sunlit bedroom. She stands with
her weight on her right leg and her hands on her hips, smiling slightly at the camera. White linen curtains hang behind
her on the left and an unmade bed is in the background. Soft morning daylight comes from a window on the left. Natural
colors, visible skin texture.
```

Ejemplo, vestida (el mismo personaje; cambian ropa, escena y luz, y todo eso está escrito):

```text
A medium shot photograph of zk4rla, a woman, sitting at a wooden table in a busy café at night. She wears a fitted
mustard-yellow ribbed knit dress with long sleeves and small gold hoop earrings. She holds a white ceramic coffee cup
with both hands and looks out of the window to the right, with a neutral expression. Warm tungsten lights hang from the
ceiling and the street outside is dark blue. Shot on a smartphone, slight noise.
```

Archivos: `nombre.png` + `nombre.txt` en la misma carpeta (formato que leen musubi-tuner y AI Toolkit).

## Fase 6 — Entrenamiento

### Sobre qué modelo entrenar

Z-Image Turbo está destilado: entrenar una LoRA directo sobre él rompe la "trayectoria" de 8 pasos (imágenes borrosas a
8 pasos, correctas a 30). Hay tres caminos:

| Camino | Inferencia en Turbo | Estado |
|---|---|---|
| **A. Z-Image base** (`Tongyi-MAI/Z-Image`, ene-2026) | Funciona; reportes de que la identidad sale **más débil** y requiere fuerza de LoRA > 1 (hasta 2–2,5 en algunos casos) | Lo que recomienda hoy musubi-tuner. Varios reportes dicen que la similitud final es mejor |
| **B. Turbo + training adapter** (`ostris/zimage_turbo_training_adapter`, v2) | Fuerza ~0,8–1,0, mantiene los 8 pasos | Ostris lo describe como "un hack": bueno para corridas cortas (personaje); en corridas largas acumula deriva |
| C. `ostris/Z-Image-De-Turbo` | Igual que B | Alternativa previa a la salida de base |

Recomendación: **entrenar A y B con el mismo dataset y comparar** con la batería de la Fase 7 sobre el modelo que usas de
verdad (CyberRealistic v9). Ojo: ninguno de los dos se entrena sobre CyberRealistic. Es un finetune de Turbo y el
adapter fue hecho para el Turbo oficial. La LoRA transfiere porque la arquitectura es la misma, y como el set se generó
con CyberRealistic, el estilo de las imágenes ya coincide con el de la inferencia.

Precisión: los reportes apuntan a bf16 al entrenar sobre base y a fp16 sobre Turbo; musubi-tuner dice que aún no está
claro. Es un parámetro más a fijar en el A/B.

### Parámetros de partida (30–40 imágenes)

| Parámetro | Valor | Por qué |
|---|---|---|
| Rank / alpha | 32 / 32 (16 si hay sobreajuste) | Hay que aprender cara **y** cuerpo; rank 8 queda corto para eso |
| Learning rate | 1e-4, AdamW8bit, constante con warmup corto | Estándar en LoRAs de DiT |
| Pasos | ~80–100 épocas (2.500–3.500 con batch 1) | Guardar cada 250 pasos y elegir después; no confiar en el último |
| Batch | 1 (máx. 2) | Batch grande con pocas imágenes desestabiliza la identidad |
| Resoluciones | buckets 512 / 768 / 1024 | Multi-resolución generaliza mejor a encuadres distintos |
| Timesteps (musubi) | `--timestep_sampling shift --discrete_flow_shift 2.0` | Lo que sugiere la documentación; ajustable |
| Caption dropout | 0–5 % | Más alto hace que la LoRA "salga sola" sin trigger (mala señal para desnudos o ropa no pedidos) |

### Dónde entrenar

La RTX 3070 (8 GB) **alcanza solo con recortes**. Con
[musubi-tuner](https://github.com/kohya-ss/musubi-tuner/blob/main/docs/zimage.md): embeddings de texto y latentes
**pre-cacheados** (Qwen3 no queda cargado durante el entrenamiento), `--fp8_base --fp8_scaled` (pesos en fp8 y cálculo
en bf16, válido en Ampere), `--gradient_checkpointing` y `--blocks_to_swap` (hasta 28 bloques a RAM). Con eso, 512 px
anda y 768 px "a veces": útil para pruebas y para un personaje, a costa de horas por corrida *(probar el s/paso real)*.
Implica bajar ComfyUI a 0 réplicas (la VRAM y los 23 GB de RAM de `k3s-node-1` no alcanzan para ambos) y Plex y Ollama
sin cargar la GPU.

Para la corrida final a 1024: GPU de alquiler (RunPod o similar, 4090/5090/A6000) con AI Toolkit o musubi-tuner. Una
corrida de 3.000 pasos tarda ~1 h en una 5090 y cuesta pocos dólares. Flujo propuesto: **iterar el dataset y los
captions en local a 512, y entrenar la versión final afuera**.

Conversión para ComfyUI (musubi): `convert_lora.py --target other`. AI Toolkit ya exporta en formato ComfyUI.

## Fase 7 — Evaluación (elegir checkpoint y fuerza)

Una batería fija de 10–14 prompts con **seeds fijas** (con Turbo, seed fija = cada diferencia es atribuible a la LoRA),
todo **fuera del set**:

| Prueba | Qué detecta |
|---|---|
| Desnuda de pie, acostada y de espaldas, en lugares que no estaban en el set | Cuerpo aprendido; si aparece ropa del set, hay clothing bleed |
| 3 atuendos y colores que no estaban en el set (traje de neopreno, vestido de gala rojo, overol) | Obediencia de la ropa |
| Situaciones nuevas (cocinando, en bicicleta bajo la lluvia, en una oficina) | Generalización de pose y contexto |
| Luz nueva (contraluz al atardecer, flash nocturno) | Si la cara depende de la luz del set |
| Otra persona en la escena (`zk4rla ... next to an older man with a grey beard`) | Fuga de identidad a terceros |
| El mismo prompt **sin trigger** | La LoRA no debe imponer la cara a cualquier mujer |
| Peinado distinto (si se entrenó variable) | Flexibilidad del pelo |
| Primer plano neutro | Parecido puro (score ArcFace) |

Elegir **el último checkpoint que todavía obedece la ropa y la desnudez** (no el de mejor parecido: suele ser uno que ya
sobreajusta). Barrer la fuerza 0,6 / 0,8 / 1,0 / 1,2 (hasta 2,5 en el camino A).

Síntomas:

- Cara correcta pero siempre la misma ropa o fondo → prenda o fondo repetidos en el set o sin describir en el caption.
- Desnudo pedido y aparece ropa → pocos desnudos o desnudez no escrita en los captions.
- Cuerpo desnudo que no corresponde → pocos desnudos de cuerpo entero, o cuerpos inconsistentes en el set.
- Cara de tercero igual al personaje → sobreajuste: checkpoint anterior, menos fuerza o rank 16.
- Colores quemados o piel plástica → fuerza demasiado alta o sobreentrenamiento, no el prompt.

## Fase 8 — Segunda vuelta (bootstrapping)

Solo con prompts, Turbo no sostiene la identidad en ángulos extremos, acciones complejas o planos muy amplios. Con la
LoRA v1 se generan 40–80 imágenes **de lo que faltaba** (acciones, ángulos, ropa difícil, más desnudos variados), se
curan con el mismo criterio (ArcFace + ojo), se mezclan con las mejores del set original y se entrena la v2. Ojo con la
deriva: cada vuelta copia los defectos de la anterior, así que hay que curar con más rigor, no con menos.

## Resumen operativo

1. Hoja de identidad distintiva, adulta y fija → casting con 8–16 seeds y ajuste del texto.
2. 50–70 prompts con la identidad copiada al inicio y ejes decorrelacionados; ~30 % desnudos repartidos en todos los
   encuadres y escenas; FaceDetailer con el mismo bloque.
3. Seleccionar 30–40 en SmartGallery (colección por personaje) + filtro ArcFace.
4. Caption = prompt sin identidad + trigger + clase, corregido contra la imagen.
5. Entrenar A (base) y B (Turbo + adapter v2), rank 32, 1e-4, ~3.000 pasos, checkpoints cada 250.
6. Batería fija con seeds fijas en CyberRealistic: elegir el último checkpoint que obedece ropa y desnudez.
7. v2 con bootstrapping de lo que falló.

## Fuentes

- musubi-tuner, [docs/zimage.md](https://github.com/kohya-ss/musubi-tuner/blob/main/docs/zimage.md): entrenamiento
  sobre base, De-Turbo y adapter, opciones de memoria.
- [Tongyi-MAI/Z-Image, discusión #18](https://huggingface.co/Tongyi-MAI/Z-Image/discussions/18): base vs Turbo,
  fuerza de LoRA, bf16/fp16 (reportes de la comunidad, sin postura oficial).
- [ostris/zimage_turbo_training_adapter](https://huggingface.co/ostris/zimage_turbo_training_adapter) y
  [ostris/Z-Image-De-Turbo](https://huggingface.co/ostris/Z-Image-De-Turbo).
- [De-distilling Z-Image-Turbo for LoRA training](https://lilting.ch/en/articles/z-image-turbo-lora-dedistill-adapter).
- [Training a reusable character LoRA for Z-Image-Turbo](https://smeltcore.com/guides/training-a-reusable-character-lora-for-z-image-turbo/):
  dataset por encuadres, captions sin identidad, elección del checkpoint.
- [Engineering notes (Hugging Face)](https://huggingface.co/blog/content-and-code/training-a-lora-for-z-image-turbo).
- Reporte técnico de Z-Image (arXiv 2511.22699): encoder causal, destilación DMD + RL, sesgos por defecto.
