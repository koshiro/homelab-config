#!/usr/bin/env bash
# Monta el directorio NFS de TrueNAS (datos del servidor Minecraft) en tu Mac
# para poder añadir datapacks sin perder datos.
#
# Uso: ./mount-nfs.sh [mount | umount]
# Sin argumentos: monta si no está montado, desmonta si ya está montado.

NFS_SERVER="192.168.1.20"
NFS_PATH="/mnt/homelab-storage/minecraft-server"
MOUNT_POINT="${HOME}/minecraft-server-data"

case "${1:-}" in
  mount)
    if mount | grep -q " on ${MOUNT_POINT} "; then
      echo "Ya está montado en ${MOUNT_POINT}"
      exit 0
    fi
    mkdir -p "$MOUNT_POINT"
    echo "Montando ${NFS_SERVER}:${NFS_PATH} en ${MOUNT_POINT} ..."
    # -o resvport y vers=3 suelen ayudar con TrueNAS; si falla, revisa el export en TrueNAS (ver DATAPACKS.md)
    sudo mount -t nfs -o resvport,vers=3 "${NFS_SERVER}:${NFS_PATH}" "$MOUNT_POINT"
    echo "Montado. Datapacks van en: ${MOUNT_POINT}/world/datapacks/"
    ;;
  umount|unmount)
    if mount | grep -q " on ${MOUNT_POINT} "; then
      sudo umount "$MOUNT_POINT"
      echo "Desmontado ${MOUNT_POINT}"
    else
      echo "No estaba montado en ${MOUNT_POINT}"
    fi
    ;;
  *)
    if mount | grep -q " on ${MOUNT_POINT} "; then
      echo "Montado en ${MOUNT_POINT}"
      echo "  Datapacks: ${MOUNT_POINT}/world/datapacks/"
      echo "  Para desmontar: $0 umount"
    else
      echo "No montado. Para montar: $0 mount"
    fi
    ;;
esac
