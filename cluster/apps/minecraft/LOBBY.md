# Lobby de juegos y red de servidores – Minecraft

Pensado para jugar 2 personas: un jugador Java (laptop) y uno Bedrock (celular/tablet, 10 años).
Para el jugador es **un solo servidor** (`minecraft.danielriquelme.cl`, Java 25565 / Bedrock 19132):
entra a un lobby de Halloween y elige a qué jugar hablando con NPCs. Por detrás hay un proxy
Velocity con tres servidores Paper 26.2.

```
Java 25565/TCP ─┐                      ┌─ principal  (supervivencia, lobby, OneBlock, parkour, minijuegos)
                ├─ proxy Velocity ─────┼─ spiral2    (Parkour Spiral 2, Hielke)
Bedrock 19132 ──┘  + Geyser/Floodgate  └─ spiral3    (Parkour Spiral 3, Hielke)
Voice chat 24454/UDP ─────────────────────► principal (directo)
```

## Cómo se usa

- **Al conectarse** todos aparecen en el lobby (`join-destination: w:lobby` en `Multiverse-Core/config.yml`).
- **Volver al lobby:** `/lobby` (o `/hub`) desde cualquier lugar, incluidos los Parkour Spiral; en el
  mundo familiar también el portal **LOBBY** (x 63–66, y 96–100, z 31).
- **NPCs del lobby** (clic o toque en la tablet):

| NPC | Personaje | Lleva a |
|---|---|---|
| **ONE BLOCK** | bruja | `/ob`: crea o vuelve a la isla propia (BentoBox AOneBlock) |
| **PARKOUR** | esqueleto | mundo `parkour`: 5 niveles (Colores, Bosque, Nether, Hielo y cielo, Gran final); la meta de cada nivel lleva al siguiente; placa roja «Volver al Nivel 1»; checkpoints en placas doradas |
| **PARKOUR SPIRAL 2** | enderman | servidor `spiral2` |
| **PARKOUR SPIRAL 3** | esqueleto glacial | servidor `spiral3` |
| **MINIJUEGOS** | zombi | mundo `minijuegos` (Minigames With Friends) |
| **MUNDO FAMILIAR** | aldeano | `mvtp w:world`: Multiverse-Inventories lo deja en su **última ubicación** de supervivencia; la primera vez, en el spawn junto al portal LOBBY (64.5, 96, 33.5) |

- **OneBlock en pareja:** `/ob team invite <jugador>` y el otro `/ob team accept`. Los jugadores
  Bedrock llevan un punto delante del nombre (p. ej. `.ArrozK`).
- **Minijuegos** (los inicia un operador, dentro de `minijuegos`): `/mg EnableGamemode BlockShuffle`
  → `/mg start`; terminar con `/mg stop`. Para un niño de 10 años: **Block Shuffle** y **Would You
  Rather**. Los modificadores (gravedad, drops aleatorios) solo en `minijuegos`. Reiniciar el
  mundo: `mv regen minijuegos`.

## Lobby Halloween

- Construcción **«Halloween Spawn» de sophiesaurus** (Planet Minecraft). La autora pide no
  republicarla: el schematic **no está en el repo**; vive en el volumen
  (`plugins/WorldEdit/schematics/halloweenspawn.schem`) y el original en el `.zip` descargado.
- Mundo `lobby` vacío (bioma bosque oscuro, anochecer fijo `time 14000`, aventura, pacífico, sin
  hambre ni daño por caída). Pegado con `//world lobby` → `//schem load halloweenspawn.schem` →
  `//paste -o` (coordenadas originales: x −1242…−1125, y −24…157, z −1176…−1057).
- Spawn en la plaza: (−1185, 38, −1089) mirando al norte. NPCs con **FancyNpcs** en arco frente al
  spawn (`lobby/build_npcs.py`); sus nombres son armor stands (`lobby_holo`) porque Geyser no
  muestra las entidades de texto de FancyNpcs en Bedrock.

## Proxy Velocity (desde 2026-10-03)

| Pieza | Detalle |
|---|---|
| `proxy/` | Velocity **4.2.0** (build 30) con Geyser y Floodgate para Velocity y el plugin propio `homelab-lobby`. Sin estado: config desde ConfigMaps/Secret |
| ¿Por qué 4.2 y no 3.5.1? | Geyser actual usa Adventure 5.2 (`GsonComponentSerializer.toBuilder()`), que Velocity 3.5.1 no trae → Geyser fallaba al arrancar |
| `proxy/plugin/LobbyPlugin.java` | `/lobby` y `/hub`: fuera del principal → conecta al principal; en el principal → deja pasar el comando al alias `/lobby` de Paper (mvtp al mundo lobby). Se compila en el arranque (initContainers `fetch-velocity-api` + `build-lobby-plugin`) |
| Identidad | Proxy en `online-mode = false` como el servidor original → mismos UUID Java; Floodgate con la **misma `key.pem`** y prefijo `.` → mismos UUID Bedrock |
| Configs de plugins | `velocity.toml` llega por `/config`; `forwarding.secret` (la imagen no interpola `${CFG_…}` en archivos `.secret`: Velocity usaba el texto literal y los backends respondían «Unable to verify player details»), las de Geyser/Floodgate y la `key.pem` las copia el initContainer `seed-plugin-configs` (el sync de `/config` deja los archivos anidados en una carpeta con marca de tiempo y Floodgate generaba otra clave). Verificar: `sha256sum` de `plugins/floodgate/key.pem` igual en proxy, principal y Spirals |
| Whitelist | Solo en el principal (`try = ["principal"]`): si te expulsa no hay segundo intento. Los Spiral no se exponen fuera del cluster |
| Reenvío | `player-info-forwarding-mode = "MODERN"`; los Paper aceptan solo al proxy vía `velocity-patch.json` (`PATCH_DEFINITIONS`, secreto `CFG_VELOCITY_SECRET`) |
| Secreto | `proxy/secret-velocity.sops.yaml` (`forwarding-secret`, `floodgate-key.pem`) |
| Services | `minecraft` (LB 25565/TCP + 19132/UDP → proxy), `minecraft-voice` (LB 24454/UDP → principal), `minecraft-backend`, `minecraft-spiral2/3` (internos) |
| Voice chat | Solo funciona en el principal (Simple Voice Chat no pasa por el proxy) |
| Skins | SkinsRestorer en el **proxy** (`MODRINTH_PROJECTS` + `MINECRAFT_VERSION`); el del Paper principal queda en `proxyMode: AUTO` |
| Alias Java → Bedrock | `JAVA_ALIASES` en `proxy/deployment.yml` (`nombreJava=nombreBedrock@uuid`): ese nombre en Java entra con el UUID y nombre de Floodgate del jugador Bedrock → mismo inventario, posición, whitelist e isla. Hoy: `.ArrozK` (PC de su madre) = `.ArrozK` (tablet). No pueden estar conectados los dos a la vez (mismo UUID). Recibe la última skin traída de Bedrock desde el último reinicio del proxy |
| Skins Bedrock | `proxy/plugin/BedrockSkins.java`: en cada conexión toma la skin que envía la tablet (datos de cliente de Geyser), la firma con **MineSkin** (clave `mineskin-api-key` del secreto, variable `MINESKIN_API_KEY`) y la pone en el perfil después de Floodgate. Motivo: la API global de GeyserMC no sube skins nuevas desde 2026-09 ([Geyser#6699](https://github.com/GeyserMC/Geyser/issues/6699)) y Floodgate mostraba una skin vieja de otra persona. Cambiar de skin en Bedrock → se ve al reconectar. Log: `Skin Bedrock de …`; copia del PNG en `plugins/homelab-lobby/bedrock-skins/`. Si Geyser arregla el error, se puede retirar |
| Filtro de hostname | `proxy/plugin/HostnameFilter.java`: los escáneres de IPv4 (p. ej. `matscan`, 2026-10) entraban por el 25565 abierto con nombres al azar tipo `BoldDeer3791` y disparaban el aviso del bot de whitelist cada ~15 min. El proxy descarta ping y login cuyo host del handshake no esté en `ALLOWED_HOSTS` (`minecraft.danielriquelme.cl`) ni sea local (Geyser entra con la dirección del proxy). Log: `Ping descartado …` / `Login descartado …`. Quien entre por IP pelada queda fuera: usar el dominio |

## Parkour Spiral 2 y 3 (`spirals/`)

- Mapas de [Hielke Maps](https://hielkemaps.com) ya en formato 26.2 (`DataVersion 4903`), con
  5 datapacks (lógica, cronómetro, entrenamiento…): por eso cada uno es el mundo principal de su
  propio Paper. Se descargan en el primer arranque (`WORLD=https://hielkemaps.com/downloads/…zip`)
  y el progreso queda en su PVC `local-path`. Reiniciar un mapa: borrar el PVC.
- Paper descarta el `game_rules.dat` de los mapas por reglas `axiom:*` del editor Axiom; las 58
  reglas `minecraft:*` originales se reaplicaron con `/gamerule` (tiempo detenido, keep_inventory,
  reaparición inmediata, sin mobs…). Si se regenera un mapa, repetirlo (ver historial del commit
  del 2026-10-03).

## Mundos y configuración del principal

| Pieza | Detalle |
|---|---|
| Plugins (Modrinth, `deployment.yml`) | Multiverse-Core, -Inventories, -Portals, -CommandDestination, BentoBox (+ AOneBlock por initContainer), Minigames With Friends, WorldEdit, FancyNpcs. Floodgate (whitelist Bedrock con `fwhitelist`) |
| Mundos | `lobby`, `parkour` (vacíos, aventura); `minijuegos` (normal, fácil); `oneblock_world*` (BentoBox); `world*` (supervivencia familiar). El laberinto se eliminó el 2026-10-03 |
| Inventarios (`config/multiverse-inventories.groups.yml`) | `default` (world + nether + end), `juegos` (lobby), `parkour`, `minijuegos`, `oneblock`. `last_location` activo, `apply-last-location-for-all-teleports: true` y `disabled-shares: [last_location]` en `juegos`, `parkour` y `minijuegos` (llegan a su spawn); `default` (supervivencia) y `oneblock` (desde 2026-10-04) recuerdan dónde salieron o se desconectaron (OneBlock: la primera vez, `/ob` lleva a la isla). **No usar el destino `ll:`**: lee el perfil solo si está en caché y si no manda al spawn (2026-10-03: dos muertes por caída en el spawn viejo) |
| Portales (`config/multiverse-portals.portals.yml`) | `familiar_lobby` (mundo familiar → lobby) y los dos del parkour; `enforce-portal-access: false` |
| NPCs (`config/fancynpcs.npcs.yml`) | copia de `plugins/FancyNpcs/npcs.yml` |
| `/lobby` en Paper | alias en `commands.yml` + permiso por defecto `multiverse.teleport.self.w.lobby` en `permissions.yml` |
| Reinicio diario | `restart-cronjob.yml`: 05:00 reinicia **proxy** (Geyser/Floodgate al día para Bedrock) y principal |

Los archivos de `config/` son copias de lo que vive en el volumen (`nvme/k8s/minecraft`).

## Reconstruir

```bash
cd cluster/apps/minecraft/lobby
python3 build_parkour.py | kubectl -n minecraft exec -i deploy/minecraft -c minecraft -- rcon-cli
python3 build_npcs.py    | kubectl -n minecraft exec -i deploy/minecraft -c minecraft -- rcon-cli
```

## Cuidados

- **Restaurar el inventario de un jugador:** con el principal detenido (`scale --replicas=0`), copiar
  desde un snapshot **todo** su estado a la vez: `world/players/data/<uuid>.dat`,
  `plugins/Multiverse-Inventories/players/<uuid>.json` y sus `groups/*/<nombre>.json` y
  `worlds/*/<nombre>.json`. Si solo se restaura el perfil del grupo, al entrar Multiverse-Inventories
  guarda el estado vanilla actual encima (pasó el 2026-10-03).
- **Spawn de supervivencia:** (64.5, 96, 33.5), junto al portal LOBBY (`setworldspawn` + `spawn-location`
  de `minecraft:overworld` en `Multiverse-Core/worlds.yml`).

- **Snapshots:** `zfs snapshot nvme/k8s/minecraft@<nombre>` antes de cambios grandes
  (`pre-lobby-20261002`, `pre-borrar-laberinto-20261003`, `pre-proxy-20261003`).
- **`portals.yml` a mano:** incluir `version: 1.3` en cada portal (sin `version`, Multiverse-Portals
  convierte `action` en `MemorySection[...]`). Verificar con `mvp list` / `mvp info <portal>`.
- **WorldEdit desde RCON:** los comandos de doble barra van como `//comando`; los schematics
  copiados después del arranque no se indexan hasta reiniciar; cargar con el nombre completo
  (`halloweenspawn.schem`).
- **26.x:** gamerules con nombres nuevos (`minecraft:keep_inventory`, `advance_time`…); tiempo por
  mundo; `setworldspawn`/`spawnpoint` piden dos ángulos; textos NBT en SNBT.
- **Checkpoints:** `enforce-respawn-at-world-spawn: false` en `Multiverse-Core/config.yml`.
- **Bedrock:** Geyser (en el proxy) soporta Bedrock 26.30–26.51 (2026-10-02). Si la tablet no
  entra tras actualizar la app: `kubectl -n minecraft rollout restart deploy/minecraft-proxy`.
- **Minecraft 26.3:** cuando Geyser lo soporte (ver `docs/PENDIENTES.md`), actualizar también los
  Spiral y revisar Velocity.
