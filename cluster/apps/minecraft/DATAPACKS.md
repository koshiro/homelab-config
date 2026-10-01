# Datapacks

Instalados (Vanilla Tweaks, MC 26.2): AFK Display, Durability Ping, More Mob Heads, Player Head Drops, Track Raw Statistics, Track Statistics, Wandering Trades. Ubicación: `/data/world/datapacks/` en el pod.

## Actualizar o añadir

1. Descargar para la versión del servidor desde https://vanillatweaks.net/picker/datapacks/ (o por API: `POST https://vanillatweaks.net/assets/server/zipdatapacks.php` con `packs` y `version`).
2. Copiar al pod y dejar dueño uid 1000:

```bash
P=$(kubectl -n minecraft get pod -l app=minecraft -o jsonpath='{.items[0].metadata.name}')
kubectl -n minecraft cp "pack.zip" "$P:/data/world/datapacks/pack.zip" -c minecraft
ssh root@192.168.1.100 'chown 1000:1000 /nvme/k8s/minecraft/world/datapacks/*'
```

3. Activar: `kubectl -n minecraft rollout restart deploy/minecraft` (o `/reload` como op).
4. Revisar errores: `kubectl -n minecraft logs deploy/minecraft -c minecraft | grep ERROR`.

Al subir de versión de Minecraft, los datapacks también deben actualizarse (los de otra versión fallan al parsear loot tables).
