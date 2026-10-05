# Buscador de semillas – próximo mundo familiar (Java 26.2)

Objetivo: elegir con mi sobrino una semilla **entretenida y con la mayor diversidad en el menor espacio posible**
alrededor del spawn: aldeas, Trial Chambers, outposts/mansiones, templos, biomas raros, Sulfur Caves y
**spawners dobles o triples** para granjas de XP. El spawn se fija en el origen (0,0) con `setworldspawn`
(los jugadores llegan por el NPC del lobby), así que todo se mide desde ahí.

No es una base de datos de semillas: solo se guardan las que pasan los filtros duros y la tabla se recorta a
las 1.000 mejores; del resto quedan contadores en `stats.json`.

## Flujo v2 (2026-10-05)

1. **Prefiltro** (`tools/starter-v3.json`, MCSeedFinder `find`, ~16.000 semillas/s, pasa 1 de cada 200):
   aldea < 250, 2 aldeas < 500, Trial < 400, outpost < 800 o mansión < 1500, templo/iglú/cabaña < 700,
   tierra en el origen.
2. **Extracción + puntaje** (`tools/runner2.py`, ~25 semillas/s con 7 workers en k3s-node-1): estructuras a 2 km
   (`check` con `HIT_CAPACITY=4096`) + biomas (`tools/biomefeat2.c`) → `tools/scoring2.py`. Pasa todos los
   filtros ~2 %.
3. **Spawners reales** (`verifier.yaml` + `tools/spawners.py`): Paper 26.2 con Multiverse y Chunky, fuera de
   k3s-node-1, ~5 min por semilla. Por cada finalista pregenera 400 m alrededor del origen (~800×800 bloques),
   lee los `.mca` (en 26.x el block entity es `minecraft:mob_spawner`) y busca grupos de 2 o 3 spawners de
   dungeon activables a la vez (existe un punto a ≤ 16 bloques de todos). Las arañas de cueva de las minas se
   descartan (comunes y malas para granjas de XP). Los dungeons no se pueden predecir sin generar el terreno.
4. **Ranking** (`tools/ranking.py`): puntaje v2 + bonus del mejor grupo de spawners: triple 25, doble 12,
   × peso promedio del mob (esqueleto 1, zombi 0,75, araña 0,4) × distancia (1 hasta 150 m, 0,4 a 400 m).

### Puntaje v2 (`tools/scoring2.py`)

- Puntos absolutos, sin percentiles (v1 aplastaba el top: todo 0,96–1,00).
- **Estructuras:** cada tipo cuenta una vez (la más cercana), valor por rareza/interés, utilidad 1 hasta `d_full`
  y lineal a 0 en `d_zero`. Mansión 15, aldea 12 (+6 y +3 por la 2.ª y 3.ª), outpost 10, templos/iglú/cabaña 6–7,
  Trial 6 (son muy comunes), portales/naufragios 3. Ciudad antigua y fortaleza puntúan en una banda.
- **Biomas:** familias jugables (plains + sunflower_plains = una); ríos y playas no cuentan. Raras valen más:
  champiñones 7, badlands/ice spikes/pale garden 5, cherry/mangrove/bamboo 4.
- **Cuevas:** Sulfur 8, Lush 4, Dripstone 3.
- **Compacto:** hasta 20 puntos si 10 atracciones distintas caben en 300 m (`R10`), 0 desde 900 m.
- **Filtros duros:** aldea ≤ 250, 2 aldeas ≤ 500, Trial ≤ 400, Sulfur ≤ 400, outpost ≤ 800 o mansión ≤ 1500,
  ≥ 75 % de tierra a 200 m, sin Deep Dark ni ciudad antigua a < 250 m, ≥ 7 tipos de estructura a 700 m y
  ≥ 6 familias de bioma (valor ≥ 2) a 500 m.

## Uso

```bash
# búsqueda (pod con GPU y /work en NFS); desacoplada de la sesión: la red puede ser intermitente
kubectl apply -f workbench.yaml
kubectl -n minecraft cp tools/<archivo> seedfinder:/work/<archivo>   # runner2.py, scoring2.py, biomefeat2.c, starter-v3.json, ranking.py
kubectl -n minecraft exec seedfinder -- sh -c 'cd /work && nohup python3 runner2.py --run /work/runs/r2 > runs/r2.log 2>&1 </dev/null &'
kubectl -n minecraft exec seedfinder -- tail -2 /work/runs/r2.log          # avance
kubectl -n minecraft exec seedfinder -- python3 /work/ranking.py /work/runs/r2 --top 15
# detener (guarda tabla y stats): kill -INT al proceso principal, no pkill -f desde un sh -c con el mismo patrón
kubectl -n minecraft exec seedfinder -- sh -c 'kill -INT $(pgrep -o -f "[r]unner2.py --run")'

# spawners (lee /work/runs/r2/finalistas.json, escribe spawners.jsonl)
kubectl -n minecraft cp tools/spawners.py seedfinder:/work/spawners.py
kubectl apply -f verifier.yaml
kubectl -n minecraft logs deploy/seed-verifier -c verifier -f
```

Compilar `biomefeat2`: `clang -O3 -march=native -I$C -o biomefeat2 biomefeat2.c $C/{biomenoise,biomes,generator,layers,noise,util,terrainnoise}.c -lm`
con `C=MCseedFinder/vendor/cubiomes`.

## Herramientas evaluadas (2026-10-04)

- **MCSeedFinder** (69gg, MIT, 26.2, CUDA): motor elegido. Validado contra Paper 26.2 con la semilla del mundo
  actual: 241/245 estructuras predichas existen (fallan una pirámide de la jungla —altura aproximada— y 3 minas),
  51/52 reales detectadas. Solo lista 8 coordenadas por tipo (`HIT_CAPACITY`); para características se compila
  una copia con 4096 en `/work/MCseedFinder-full`. `find` no emite nada hasta terminar → tandas. Con condiciones
  frecuentes la GPU no gana (el trabajo es de biomas en CPU). `biome_near` subterráneo (Sulfur) es muy lento
  (~42 semillas/s): va en `biomefeat2`, no en el prefiltro. No predice dungeons.
- **mc-worldgen-seed-lab**: generador 26.x verificado bloque a bloque; candidato para terreno/relieve y mapas.
- **JUNO**: solo 26.3 y solo variedad de biomas; no aplica.

## Historial

- `r1` (2026-10-04, v1: `runner.py`, `biomefeat.c`, `score.py`, `starter-v2.json`): 620.028 semillas, 6 GB con
  todas las coordenadas. El puntaje por percentiles no distinguía las buenas (la #1 no era de las mejores).

## Para jugar la ganadora

Revisarla en la laptop con **Java 26.2 exacto** (26.3 cambió el ruido de biomas: misma semilla, otro mundo).
En el servidor: crearla con Multiverse, `setworldspawn` en el origen y **pregenerar ~3 km con Chunky antes de
actualizar a 26.3**.
