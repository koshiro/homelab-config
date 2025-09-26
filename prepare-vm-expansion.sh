#!/bin/bash
# Script para preparar la VM k3s-node-1 para expansión de disco
# Ejecutar DESPUÉS de expandir el disco en Proxmox

set -euo pipefail

echo "=== PREPARACIÓN DE VM PARA EXPANSIÓN ==="
echo "Fecha: $(date)"
echo ""

# 1. Verificar estado actual
echo "=== ESTADO ACTUAL DEL DISCO ==="
df -h /
echo ""
lsblk
echo ""

# 2. Verificar si hay espacio sin particionar
echo "=== VERIFICANDO ESPACIO SIN PARTICIONAR ==="
if [ -b /dev/sda ]; then
    DISK="/dev/sda"
elif [ -b /dev/nvme0n1 ]; then
    DISK="/dev/nvme0n1"
else
    echo "❌ No se pudo identificar el disco principal"
    exit 1
fi

echo "Disco principal: $DISK"
fdisk -l $DISK | tail -10
echo ""

# 3. Verificar si usa LVM
echo "=== VERIFICANDO LVM ==="
if command -v pvs >/dev/null 2>&1; then
    echo "✅ LVM detectado:"
    pvs
    vgs
    lvs
    echo ""
    echo "=== EXPANSIÓN CON LVM ==="
    echo "1. Crear nueva partición: fdisk $DISK"
    echo "2. Crear PV: pvcreate ${DISK}2"
    echo "3. Extender VG: vgextend ubuntu-vg ${DISK}2"
    echo "4. Extender LV: lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv"
    echo "5. Redimensionar FS: resize2fs /dev/ubuntu-vg/ubuntu-lv"
else
    echo "❌ LVM no detectado - expansión manual requerida"
    echo "=== EXPANSIÓN SIN LVM ==="
    echo "1. Crear nueva partición: fdisk $DISK"
    echo "2. Formatear: mkfs.ext4 ${DISK}2"
    echo "3. Montar temporalmente: mkdir /mnt/new && mount ${DISK}2 /mnt/new"
    echo "4. Copiar datos: cp -a /var/lib/containerd/* /mnt/new/"
    echo "5. Actualizar fstab y remontar"
fi

echo ""
echo "=== LIMPIEZA RECOMENDADA ANTES DE EXPANSIÓN ==="
echo "1. Limpiar imágenes Docker/containerd:"
echo "   k3s crictl images prune"
echo "   k3s crictl rmi \$(k3s crictl images -q)"
echo ""
echo "2. Limpiar logs:"
echo "   journalctl --vacuum-time=7d"
echo "   find /var/log -name '*.log' -mtime +7 -delete"
echo ""

echo "=== FIN DE PREPARACIÓN ==="
