# Añadir datapacks al servidor (sin perder datos)

Los datos del servidor están en TrueNAS. Para añadir datapacks sin tocar el resto:

## 0. Si sale "Permission denied" al montar (TrueNAS)

El export NFS en TrueNAS tiene que permitir a tu Mac:

1. **TrueNAS CORE/SCALE** → **Sharing** → **Unix (NFS) Shares** → edita el share de `homelab-storage/minecraft-server`.
2. En **Authorized networks** pon tu red, p.ej. `192.168.1.0/24`, o la IP de tu Mac.
3. En **Authorized hosts** (si existe) añade la IP de tu Mac o déjalo vacío si usas Authorized networks.
4. **Maproot User** / **Mapall User**: si sigue fallando, prueba con Maproot User = `root` y Maproot Group = `wheel` (o el UID/GID de tu usuario en el Mac) para que el Mac vea los archivos como un usuario con permisos.
5. Guarda y prueba de nuevo el montaje.

## 1. Montar el directorio NFS en tu Mac

Desde esta carpeta:

```bash
chmod +x mount-nfs.sh
./mount-nfs.sh mount
```

(Te pedirá la contraseña de sudo.) El NFS quedará montado en **`~/minecraft-server-data`**.

## 2. Dónde poner los datapacks

Copia cada datapack (carpeta o .zip) dentro de:

```
~/minecraft-server-data/world/datapacks/
```

Si el mundo tiene otro nombre (p.ej. `world_nether` no; el mundo principal suele ser `world`), usa ese. Comprueba con:

```bash
ls ~/minecraft-server-data/
```

Verás la carpeta del mundo (normalmente `world`). Dentro, `datapacks/` es donde van los datapacks.

## 3. Activar en el juego

- **Opción A:** Reiniciar el servidor (o `kubectl rollout restart deployment/minecraft -n minecraft`).
- **Opción B:** Sin reiniciar: en el juego como op, `/reload` (puede dar lag breve).

Los datapacks se cargan al arrancar el mundo o al hacer `reload`.

## 4. Desmontar cuando termines

```bash
./mount-nfs.sh umount
```

## Seguridad de los datos

- Solo estás **añadiendo** archivos en `world/datapacks/`. No se borra ni se sobrescribe el mundo ni los jugadores.
- El montaje es **solo lectura** si quieres: no hace falta; solo evita borrar o mover cosas fuera de `datapacks/`.
- Los snapshots de TrueNAS siguen siendo el respaldo del dataset.
