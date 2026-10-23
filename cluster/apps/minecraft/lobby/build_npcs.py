#!/usr/bin/env python3
"""NPCs del lobby Halloween (FancyNpcs) + hologramas visibles en Bedrock (ver ../LOBBY.md).

FancyNpcs dibuja los nombres con entidades de texto que Geyser no muestra en Bedrock, así que los
NPC van sin nombre propio y el título/subtítulo son armor stands invisibles (tag lobby_holo).
Posiciones calculadas sobre la plaza del schematic halloweenspawn (pegado con //paste -o),
en arco frente al spawn (-1185, 38, -1089) y mirando hacia él.

Uso:  python3 build_npcs.py | kubectl -n minecraft exec -i deploy/minecraft -c minecraft -- rcon-cli
"""
# nombre, tipo, x, y, z, yaw, altura holograma, título, color, subtítulo, acciones
NPCS = [
    ("oneblock", "WITCH", -1190.5, 37, -1091.5, -63, 2.4, "ONE BLOCK", "green", "Tu isla de un bloque", [("player_command", "ob")]),
    ("parkour", "SKELETON", -1188.5, 37, -1094.5, -34, 2.4, "PARKOUR", "gold", "5 niveles", [("console_command", "mvtp {player} w:parkour")]),
    ("spiral2", "ENDERMAN", -1185.5, 37.5, -1096.5, -7, 3.3, "PARKOUR SPIRAL 2", "light_purple", "¡Sube la espiral!", [("send_to_server", "spiral2")]),
    ("spiral3", "STRAY", -1181.5, 37, -1095.5, 23, 2.4, "PARKOUR SPIRAL 3", "aqua", "La espiral gigante", [("send_to_server", "spiral3")]),
    ("minijuegos", "ZOMBIE", -1179.5, 37.5, -1092.5, 51, 2.4, "MINIJUEGOS", "dark_purple", "Block Shuffle y más", [("console_command", "mvtp {player} w:minijuegos")]),
    # EL CONEJO (mundo familiar nuevo, semilla 5327173214429367666): al frente, en la plaza central del spawn (y 38),
    # el primer NPC que se ve al entrar. Mundo `el_conejo` (survival/hard como `world`), alias "El Conejo".
    ("conejo", "RABBIT", -1185.5, 38, -1092.5, 0, 1.4, "EL CONEJO", "yellow", "Mundo nuevo", [("console_command", "mvtp {player} w:el_conejo")]),
    # MUNDO FAMILIAR (world, el mundo anterior): movido lejos del inicio, 10 bloques detrás del spawn (hay que darse vuelta).
    ("familiar", "VILLAGER", -1185.5, 37, -1079.5, 180, 2.4, "MUNDO FAMILIAR", "blue", "Supervivencia", [("console_command", "mvtp {player} w:world")]),
]

print("kill @e[type=minecraft:armor_stand,tag=lobby_holo]")
for name, typ, x, y, z, yaw, h, title, color, sub, actions in NPCS:
    print(f"npc remove {name}")
    print(f"npc create {name} --type {typ} --location {x} {y} {z} --world lobby")
    print(f"npc rotate {name} {yaw} 0")
    print(f"npc displayname {name} <empty>")
    print(f"npc turn_to_player {name} true")
    print(f"npc collidable {name} false")
    print(f"npc interaction_cooldown {name} 2s")
    for act, val in actions:
        print(f"npc action {name} any_click add {act} {val}")
    for dy, text, col, bold in ((h + 0.4, title, color, True), (h, sub, "white", False)):
        print(f"execute in minecraft:lobby run summon minecraft:armor_stand {x} {y + dy} {z} "
              f"{{Invisible:1b,Marker:1b,NoGravity:1b,Invulnerable:1b,CustomNameVisible:1b,Tags:[\"lobby_holo\"],"
              f"CustomName:{{text:\"{text}\",color:\"{col}\",bold:{str(bold).lower()},italic:{str(not bold).lower()}}}}}")
print("fancynpcs save")
