#!/usr/bin/env bash
# Copia los modelos Z Image Turbo al ComfyUI del cluster via NFS.
# Ejecutar en tu Mac con sudo (monta NFS y copia; el mount es root, por eso cp también con sudo):
#   cd cluster/apps/comfyui && sudo ./copy-z-imageturbo-models.sh
#
# Requiere: Mac en la red local (192.168.1.x) con acceso a TrueNAS.

set -e

NFS_SERVER="192.168.1.100"
NFS_PATH="/mnt/homelab-storage/comfyui"
MOUNT_POINT="/tmp/comfyui-nfs-mount"
SRC="/Users/daniel/Documents/ComfyUI/models"

FILES=(
  "diffusion_models/zImageTurbo_turbo.safetensors"
  "vae/zImageTurbo_vae.safetensors"
  "text_encoders/zImageTurbo_textEncoder.safetensors"
)

echo "=== Copiando Z Image Turbo al ComfyUI (NFS) ==="

# Crear punto de montaje
mkdir -p "$MOUNT_POINT"

# Montar NFS (pide sudo)
if ! mount | grep -q "$MOUNT_POINT"; then
  echo "Montando NFS..."
  sudo mount -t nfs -o resvport,vers=4,noatime "${NFS_SERVER}:${NFS_PATH}" "$MOUNT_POINT" || {
    echo "ERROR: No se pudo montar. ¿Estás en la red local? ¿TrueNAS accesible?"
    exit 1
  }
  UNMOUNT=1
else
  echo "NFS ya montado en $MOUNT_POINT"
  UNMOUNT=0
fi

# Crear subdirs por si no existen (con sudo: el NFS monta como root, escribir requiere mismo usuario)
sudo mkdir -p "$MOUNT_POINT/models/diffusion_models" "$MOUNT_POINT/models/vae" "$MOUNT_POINT/models/text_encoders"

# Copiar archivos (sudo: el montaje NFS es del root que ejecutó mount; cp como root escribe correctamente)
for f in "${FILES[@]}"; do
  src="$SRC/$f"
  dst="$MOUNT_POINT/models/$f"
  if [ -f "$src" ]; then
    echo "Copiando $f (~$(du -h "$src" | cut -f1))..."
    sudo cp -v "$src" "$dst"
  else
    echo "AVISO: $src no existe, omitiendo"
  fi
done

# Desmontar
if [ "$UNMOUNT" = 1 ]; then
  echo "Desmontando..."
  sudo umount "$MOUNT_POINT"
fi

echo "Completado. Los modelos estarán disponibles en ComfyUI."
