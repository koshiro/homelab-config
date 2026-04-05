# Protección de datos – Minecraft

Para **no perder datos** bajo ningún caso:

## Dónde están los datos

- **Única copia persistente**: NFS en TrueNAS  
  `192.168.1.20:/mnt/homelab-storage/minecraft-server`
- Kubernetes **no** crea ni borra ese almacenamiento. Borrar el deployment o el namespace **no** borra los datos del NFS.

## Qué hace el deployment

1. **Cierre graceful**: al parar el pod, primero se ejecuta `rcon-cli save-all` (preStop) y luego el contenedor recibe SIGTERM; el wrapper del imagen envía `/stop` al servidor para guardar y cerrar bien.
2. **Tiempo para guardar**: `terminationGracePeriodSeconds: 90` para que el servidor tenga tiempo de guardar antes de un eventual SIGKILL.
3. **Estrategia Recreate**: solo hay un pod escribiendo; no hay dos instancias escribiendo al mismo mundo.

## Qué no hacer

- **No** cambiar el `path` del volumen NFS en el deployment sin tener backup (o sin saber que apuntas a otra ruta y pierdes la actual).
- **No** borrar el dataset/carpeta `homelab-storage/minecraft-server` en TrueNAS sin backup.
- **No** reducir `terminationGracePeriodSeconds` por debajo de ~60 segundos (riesgo de SIGKILL antes de guardar).

## Respaldos

- Los snapshots automáticos en TrueNAS para el pool/dataset que contiene `homelab-storage/minecraft-server` (diarios + semanales) son el respaldo. Mantener esa política activa.
