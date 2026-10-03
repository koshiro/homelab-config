#!/usr/bin/env python3
"""Parkour para niños en 5 niveles (mundo `parkour`, ver ../LOBBY.md).

Cada nivel es un carril sobre el vacío (nivel k empieza en x=0, z=40*(k-1)), con dificultad
creciente pero amable con controles táctiles de Bedrock. Mecánicas:
  - Placa dorada = punto de control (`/spawnpoint`); caer bajo y=92 = volver al último punto
    (bloque de comandos repetidor en el chunk forzado 0,0; mundo con keep_inventory e
    immediate_respawn). Requiere `enforce-respawn-at-world-spawn: false` en Multiverse-Core.
  - Meta de cada nivel: título + fuegos artificiales y teletransporte al inicio del siguiente.
  - Inicio de los niveles 2-5: placa roja «Volver al Nivel 1».
  - Meta del nivel 5: celebración, placa «Jugar de nuevo» (Nivel 1) y portal al lobby.

Uso:  python3 build_parkour.py > parkour.txt
      kubectl -n minecraft exec -i deploy/minecraft -c minecraft -- rcon-cli < parkour.txt
Las regiones de portales para Multiverse-Portals se imprimen en stderr.
"""
import sys

W = "minecraft:parkour"
Y = 100
LANE = 40
out = []


def cmd(c):
    out.append(f"execute in {W} run {c}")


def setb(x, y, z, b):
    cmd(f"setblock {x} {y} {z} {b}")


def fill(x1, y1, z1, x2, y2, z2, b):
    cmd(f"fill {x1} {y1} {z1} {x2} {y2} {z2} {b}")


def q(text):
    """Comillas simples para el NBT Command: escapa las simples del comando."""
    return text.replace("\\", "\\\\").replace("'", "\\'")


def plate_trigger(x, y, z, top, commands, plate="minecraft:light_weighted_pressure_plate"):
    """Placa sobre `top` en (x,y,z); debajo, un bloque de comandos de impulso y los demás en cadena."""
    setb(x, y, z, top)
    setb(x, y + 1, z, plate)
    for i, c in enumerate(commands):
        kind = "command_block" if i == 0 else "chain_command_block"
        auto = "" if i == 0 else ",auto:1b"
        setb(x, y - 1 - i, z, f"minecraft:{kind}[facing=down]{{Command:'{q(c)}'{auto}}}")


def holo(x, y, z, text, color, bold=True, italic=False):
    cmd(f'summon minecraft:armor_stand {x} {y} {z} {{Invisible:1b,Marker:1b,NoGravity:1b,Invulnerable:1b,'
        f'CustomNameVisible:1b,Tags:["parkour_holo"],CustomName:{{text:"{text}",color:"{color}",'
        f'bold:{str(bold).lower()},italic:{str(italic).lower()}}}}}')


def sign(x, y, z, rot, lines, wood="cherry"):
    msgs = ",".join(l if l.startswith(("{", '"')) else f'{{text:"{l}"}}' for l in lines)
    setb(x, y, z, f"minecraft:{wood}_sign[rotation={rot}]{{front_text:{{messages:[{msgs}]}}}}")


P = "@p[distance=..6]"   # en cadena el bloque está más abajo: radio mayor


def title(text, color):
    return f'title {P} title {{text:"{text}",color:"{color}",bold:true}}'


def actionbar(text, color):
    return f'title {P} actionbar {{text:"{text}",color:"{color}",bold:true}}'


def firework(colors="16766720,65535,16711935"):
    return (f'execute at {P} run summon minecraft:firework_rocket ~ ~1 ~ {{LifeTime:20,FireworksItem:'
            f'{{id:"minecraft:firework_rocket",count:1,components:{{"minecraft:fireworks":{{explosions:'
            f'[{{shape:"star",colors:[I;{colors}],has_twinkle:true,has_trail:true}}]}}}}}}}}')


def start_of(level):
    return (0, Y + 1, LANE * (level - 1))


def goto(level):
    sx, sy, sz = start_of(level)
    return [f"spawnpoint {P} {sx} {sy} {sz} -90 0", f"tp {P} {sx + 0.5} {sy} {sz + 0.5} -90 0"]


# ---------------------------------------------------------------- definición de niveles
# Operaciones: ("s", dx, dy, dz, bloque[, extra]) bloque nuevo; ("m", dx, dy, dz) mover sin bloque;
#              ("cp",) punto de control 3x3 a 3 bloques. extra: "ladder" (pared+escalera de 4),
#              "ladder5" (de 5), "fence" (poste de cerca), "pane" (panel de vidrio).
L1 = []
L1 += [("s", 2, 0, dz, "minecraft:lime_concrete") for dz in (0, 1, 0, -1, 0)]
L1 += [("s", 3, dy, dz, "minecraft:yellow_concrete") for dy, dz in ((0, 0), (1, 1), (0, 0), (1, -1), (0, -1), (1, 0))]
L1 += [("cp",)]
L1 += [("s", 2, 0, dz, "minecraft:orange_concrete") for dz in (2, 2, 0)]
L1 += [("s", 2, 0, 0, "minecraft:orange_concrete", "ladder"), ("m", 1, 4, 0), ("s", 1, 0, 0, "minecraft:orange_concrete")]
L1 += [("s", 2, 0, dz, "minecraft:orange_concrete") for dz in (0, -1, -1, 0)]
L1 += [("cp",)]
L1 += [("s", 3, -1, 0, "minecraft:slime_block"), ("s", 2, 1, 1, "minecraft:purple_concrete"),
       ("s", 2, 0, 1, "minecraft:purple_concrete"), ("s", 3, -1, 0, "minecraft:slime_block"),
       ("s", 2, 1, -1, "minecraft:purple_concrete")]
L1 += [("s", 2, 0, dz, "minecraft:magenta_concrete") for dz in (-1, -1, 0)]
L1 += [("cp",)]
L1 += [("s", dx, 1, dz, "minecraft:light_blue_concrete")
       for dx, dz in ((2, 0), (1, 2), (-1, 2), (-2, 1), (-2, -1), (-1, -2), (1, -2), (2, -1), (2, 0))]

# Nivel 2 – Bosque: troncos, subidas, postes de cerca, escalera, hojas
LOG, LEAF, MOSS = "minecraft:oak_log", "minecraft:azalea_leaves[persistent=true]", "minecraft:moss_block"
L2 = [("s", 2, 0, 0, MOSS), ("s", 2, 0, 0, MOSS), ("s", 3, 0, 1, LOG), ("s", 3, 1, 0, LOG),
      ("s", 3, 0, -1, LOG), ("s", 2, 1, 0, LOG), ("s", 3, 0, 1, LOG)]
L2 += [("s", 2, 0, 0, LOG)]
L2 += [("s", 2, 0, dz, "minecraft:oak_fence", "fence") for dz in (0, 1, 0, -1)]
L2 += [("s", 2, 0, 0, LOG), ("cp",)]
L2 += [("s", 2, 0, 0, MOSS, "ladder5"), ("m", 1, 5, 0), ("s", 1, 0, 0, LEAF)]
L2 += [("s", 3, 0, dz, LEAF) for dz in (1, 1, 0, -1)]
L2 += [("s", 3, 1, 0, LOG), ("s", 3, 0, -1, LOG), ("s", 2, 1, 0, LOG), ("cp",)]
L2 += [("s", 3, -1, 0, LEAF), ("s", 3, -1, 1, LEAF), ("s", 3, 1, 0, LOG), ("s", 3, 1, -1, LOG)]
L2 += [("s", dx, 1, dz, "minecraft:flowering_azalea_leaves[persistent=true]")
       for dx, dz in ((2, 0), (1, 2), (-1, 2), (-2, 1), (-2, -1), (-1, -2), (1, -2), (2, 0))]

# Nivel 3 – Nether: zigzag, rebotes desde más alto, subidas
NB, RNB, CR, BS = "minecraft:nether_bricks", "minecraft:red_nether_bricks", "minecraft:crimson_planks", "minecraft:polished_blackstone"
L3 = [("s", 2, 0, 0, RNB), ("s", 2, 0, 2, NB), ("s", 2, 0, -2, NB), ("s", 2, 0, 2, NB), ("s", 2, 0, -2, NB),
      ("s", 3, 1, 0, CR), ("s", 3, 1, 1, CR), ("s", 3, 0, 0, CR), ("cp",)]
L3 += [("s", 2, 1, 0, BS, "ladder"), ("m", 1, 4, 0), ("s", 1, 0, 0, BS)]   # torre con escalera
L3 += [("s", 4, -3, 0, "minecraft:slime_block"), ("s", 2, 1, 1, RNB), ("s", 3, 0, 0, RNB),
       ("s", 4, -3, -1, "minecraft:slime_block"), ("s", 2, 1, 0, RNB), ("cp",)]
L3 += [("s", 2, 0, dz, "minecraft:nether_brick_fence", "fence") for dz in (1, 1, 0, -1, -1)]
L3 += [("s", 3, 0, 0, BS), ("s", 3, 1, 0, CR), ("s", 3, 1, 1, CR), ("s", 3, 1, -1, CR), ("s", 3, 1, 0, CR)]

# Nivel 4 – Hielo y cielo: algo de hielo resbaloso, paneles de vidrio, escaleras
ICE, PICE, SNOW, GLASS = "minecraft:packed_ice", "minecraft:blue_ice", "minecraft:snow_block", "minecraft:light_blue_stained_glass"
L4 = [("s", 2, 0, 0, SNOW), ("s", 3, 0, 1, ICE), ("s", 3, 0, -1, ICE), ("s", 3, 1, 0, SNOW), ("s", 3, 0, 1, SNOW),
      ("s", 2, 0, 0, GLASS), ("s", 2, 0, 0, GLASS), ("cp",)]
L4 += [("s", 2, 0, dz, "minecraft:light_blue_stained_glass_pane", "pane") for dz in (0, 1, 0, -1)]
L4 += [("s", 2, 0, 0, SNOW), ("s", 2, 0, 0, SNOW, "ladder5"), ("m", 1, 5, 0), ("s", 1, 0, 0, SNOW), ("cp",)]
L4 += [("s", 3, 0, 0, PICE), ("s", 3, 0, 1, PICE), ("s", 4, -1, 0, SNOW), ("s", 3, 1, 0, GLASS),
       ("s", 3, 1, -1, GLASS), ("s", 3, 0, 0, SNOW), ("s", 4, -2, 0, "minecraft:slime_block"),
       ("s", 2, 1, 0, SNOW), ("s", 2, 1, 0, SNOW)]

# Nivel 5 – Gran final arcoíris: un poco de todo, más largo
RB = ["minecraft:red_concrete", "minecraft:orange_concrete", "minecraft:yellow_concrete", "minecraft:lime_concrete",
      "minecraft:light_blue_concrete", "minecraft:blue_concrete", "minecraft:purple_concrete", "minecraft:magenta_concrete"]
L5 = [("s", 3, 0, (i % 2) * 2 - 1, RB[i % 8]) for i in range(6)]
L5 += [("s", 3, 1, 0, RB[6]), ("cp",)]
L5 += [("s", 2, 0, dz, "minecraft:cherry_fence", "fence") for dz in (1, 0, -1)]
L5 += [("s", 2, 0, 0, RB[0], "ladder"), ("m", 1, 4, 0), ("s", 1, 0, 0, RB[1])]
L5 += [("s", 3, 0, dz, RB[2 + i]) for i, dz in enumerate((1, 1, -1, -1))]
L5 += [("s", 4, -2, 0, "minecraft:slime_block"), ("s", 2, 1, 1, RB[7]), ("cp",)]
L5 += [("s", 3, 0, 0, "minecraft:packed_ice"), ("s", 3, 0, 1, "minecraft:packed_ice"),
       ("s", 2, 0, 0, "minecraft:white_stained_glass_pane", "pane"), ("s", 2, 0, 0, "minecraft:white_stained_glass_pane", "pane"),
       ("s", 2, 0, 0, RB[4])]
L5 += [("s", dx, 1, dz, RB[i % 8])
       for i, (dx, dz) in enumerate(((2, 0), (1, 2), (-1, 2), (-2, 1), (-2, -1), (-1, -2), (1, -2), (2, -1), (2, 1), (1, 2)))]

LEVELS = [
    dict(name="Colores", color="gold", plat="minecraft:lime_concrete", seq=L1),
    dict(name="Bosque", color="green", plat="minecraft:moss_block", seq=L2),
    dict(name="Nether", color="red", plat="minecraft:red_nether_bricks", seq=L3),
    dict(name="Hielo y cielo", color="aqua", plat="minecraft:snow_block", seq=L4),
    dict(name="Gran final", color="light_purple", plat="minecraft:purple_concrete", seq=L5),
]

# ---------------------------------------------------------------- limpieza
Z_MAX = LANE * len(LEVELS) + 8
cmd(f"forceload add -16 -16 136 {Z_MAX}")
cmd("kill @e[type=minecraft:armor_stand,tag=parkour_holo]")
for x0 in range(-16, 137, 24):
    for z0 in range(-16, Z_MAX + 1, 24):
        fill(x0, 84, z0, min(x0 + 23, 136), 139, min(z0 + 23, Z_MAX), "minecraft:air")

portal_regions = {}
# ---------------------------------------------------------------- construcción
for n, lv in enumerate(LEVELS, start=1):
    _, _, z0 = start_of(n)
    # plataforma de inicio 11x11
    fill(-5, Y - 1, z0 - 5, 5, Y - 1, z0 + 5, "minecraft:stone")
    fill(-5, Y, z0 - 5, 5, Y, z0 + 5, "minecraft:smooth_quartz")
    fill(-4, Y, z0 - 1, 5, Y, z0 + 1, lv["plat"])
    for x, z in ((-5, z0 - 5), (-5, z0 + 5), (5, z0 - 5), (5, z0 + 5)):
        fill(x, Y + 1, z, x, Y + 2, z, "minecraft:cherry_fence")
        setb(x, Y + 3, z, "minecraft:lantern")
    fill(-5, Y + 1, z0 - 5, 5, Y + 3, z0 - 5, "minecraft:barrier")
    fill(-5, Y + 1, z0 + 5, 5, Y + 3, z0 + 5, "minecraft:barrier")
    fill(-5, Y + 1, z0 - 5, -5, Y + 3, z0 + 5, "minecraft:barrier")
    holo(0.5, Y + 4.4, z0 + 0.5, f"NIVEL {n}", lv["color"])
    holo(0.5, Y + 4.0, z0 + 0.5, lv["name"], "white", bold=False, italic=True)
    # placa de salida: guarda el punto de reaparición del inicio del nivel
    plate_trigger(3, Y, z0, lv["plat"], [f"spawnpoint {P} 0 {Y + 1} {z0} -90 0",
                                          actionbar(f"¡Nivel {n}: {lv['name']}!", lv["color"])])
    if n == 1:
        # portal de vuelta al lobby (lado oeste, mirando al este) y carteles de bienvenida
        fill(-4, Y + 1, -2, -4, Y + 5, 1, "minecraft:obsidian")
        fill(-4, Y + 2, -1, -4, Y + 4, 0, "minecraft:nether_portal[axis=z]")
        portal_regions["parkour_volver"] = f"parkour:-4,{Y + 2},-1:-4,{Y + 4},0"
        sign(-3, Y + 1, 2, 12, ['""', '{text:"Volver",color:"dark_aqua",bold:true}', "al lobby", '""'])
        sign(0, Y + 1, -3, 0, ['{text:"PARKOUR",color:"gold",bold:true}', "5 niveles. Si", "caes, vuelves al", "punto de control"])
        sign(1, Y + 1, -3, 0, ['{text:"(placa dorada)"}', "La meta te lleva", "al nivel siguiente", '{text:"¡Suerte!",color:"dark_purple",bold:true}'])
    else:
        # placa roja: volver al nivel 1
        plate_trigger(-2, Y, z0 - 3, "minecraft:red_concrete",
                      [actionbar("Volviendo al Nivel 1", "red")] + goto(1),
                      plate="minecraft:heavy_weighted_pressure_plate")
        sign(-2, Y + 1, z0 - 4, 0, ['{text:"← NIVEL 1",color:"dark_red",bold:true}', "Pisa la placa", "roja para volver", "al principio"])
        sign(0, Y + 1, z0 - 4, 0, [f'{{text:"NIVEL {n}",color:"dark_purple",bold:true}}', lv["name"], "", '{text:"¡Tú puedes!",color:"dark_green"}'])

    # recorrido
    x, y, z = 6, Y, z0
    cps = []
    for op in lv["seq"]:
        if op[0] == "m":
            x, y, z = x + op[1], y + op[2], z + op[3]
        elif op[0] == "cp":
            x, y, z = x + 3, y, z
            cps.append((x, y, z))
        else:
            _, dx, dy, dz, block, *extra = op
            x, y, z = x + dx, y + dy, z + dz
            setb(x, y, z, block)
            kind = extra[0] if extra else None
            if kind in ("ladder", "ladder5"):
                h = 4 if kind == "ladder" else 5
                fill(x + 1, y + 1, z, x + 1, y + h, z, block)
                fill(x, y + 1, z, x, y + h, z, "minecraft:ladder[facing=west]")
    # puntos de control
    for i, (cx, cy, cz) in enumerate(cps, start=1):
        fill(cx - 1, cy, cz - 1, cx + 1, cy, cz + 1, "minecraft:gold_block")
        plate_trigger(cx, cy, cz, "minecraft:gold_block", [f"spawnpoint {P} {cx} {cy + 1} {cz} -90 0",
                                                           actionbar(f"¡Punto de control {i}!", "gold")])
        setb(cx - 1, cy + 1, cz - 1, "minecraft:lantern")
        holo(cx + 0.5, cy + 2.6, cz + 0.5, f"Punto de control {i}", "gold", bold=False)

    # meta: plataforma 7x7 con placas a lo ancho
    fx, fy, fz = x + 3, y, z
    fill(fx - 1, fy - 1, fz - 3, fx + 5, fy - 1, fz + 3, "minecraft:stone")
    fill(fx - 1, fy, fz - 3, fx + 5, fy, fz + 3, "minecraft:gold_block")
    fill(fx - 1, fy + 1, fz - 3, fx + 5, fy + 3, fz - 3, "minecraft:barrier")
    fill(fx - 1, fy + 1, fz + 3, fx + 5, fy + 3, fz + 3, "minecraft:barrier")
    fill(fx + 5, fy + 1, fz - 3, fx + 5, fy + 3, fz + 3, "minecraft:barrier")
    if n < len(LEVELS):
        holo(fx + 2.5, fy + 3.4, fz + 0.5, f"¡META NIVEL {n}!", "gold")
        holo(fx + 2.5, fy + 3.0, fz + 0.5, f"Pisa la placa → Nivel {n + 1}", "white", bold=False, italic=True)
        for dz in (-1, 0, 1):
            plate_trigger(fx + 1, fy, fz + dz, "minecraft:gold_block",
                          [title(f"¡Nivel {n} superado!", "gold"), firework()] + goto(n + 1))
    else:
        holo(fx + 2.5, fy + 4.2, fz + 0.5, "¡CAMPEONES DEL PARKOUR!", "light_purple")
        for dz in (-1, 0, 1):
            plate_trigger(fx + 1, fy, fz + dz, "minecraft:gold_block",
                          [title("¡CAMPEONES!", "light_purple"), firework("16711680,16776960,65280,255"),
                           f"spawnpoint {P} 0 {Y + 1} 0 -90 0"])
        # placa roja «jugar de nuevo» y portal al lobby
        plate_trigger(fx + 3, fy, fz + 2, "minecraft:red_concrete", [actionbar("¡Otra vez desde el Nivel 1!", "red")] + goto(1),
                      plate="minecraft:heavy_weighted_pressure_plate")
        sign(fx + 3, fy + 1, fz + 1, 4, ['{text:"JUGAR DE",color:"dark_red",bold:true}', '{text:"NUEVO",color:"dark_red",bold:true}', "placa roja →", '""'])
        fill(fx + 4, fy + 1, fz - 2, fx + 4, fy + 5, fz + 1, "minecraft:obsidian")
        fill(fx + 4, fy + 2, fz - 1, fx + 4, fy + 4, fz, "minecraft:nether_portal[axis=z]")
        portal_regions["parkour_meta"] = f"parkour:{fx + 4},{fy + 2},{fz - 1}:{fx + 4},{fy + 4},{fz}"
        holo(fx + 4.5, fy + 6.4, fz + 0.5, "Lobby", "aqua")

# Caídas: bloque de comandos repetidor bajo el inicio del nivel 1 (chunk forzado permanente)
setb(0, Y - 3, 0, 'minecraft:repeating_command_block{auto:1b,Command:"kill @a[x=-300,y=-100,z=-300,dx=600,dy=192,dz=600]"}')

cmd(f"setworldspawn 0 {Y + 1} 0 -90 0")
cmd("forceload remove all")
cmd("forceload add 0 0")   # mantiene vivo el bloque de caídas
print("\n".join(out))
print("# portales: " + " ".join(f"{k}={v}" for k, v in portal_regions.items()), file=sys.stderr)
