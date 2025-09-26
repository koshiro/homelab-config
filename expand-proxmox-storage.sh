#!/bin/bash
# Script para expandir almacenamiento de VM k3s-node-1 en Proxmox
# Ejecutar en el host Proxmox (root@pve)

set -euo pipefail

echo "=== EXPANSIÓN DE ALMACENAMIENTO VM k3s-node-1 ==="
echo "Fecha: $(date)"
echo ""

# 1. Verificar VMs disponibles
echo "=== VMs DISPONIBLES ==="
qm list | grep -E "(VMID|k3s-node-1|131)"
echo ""

# 2. Verificar estado actual de k3s-node-1
echo "=== ESTADO ACTUAL DE k3s-node-1 ==="
VMID=$(qm list | grep "k3s-node-1" | awk '{print $1}')
if [ -z "$VMID" ]; then
    echo "❌ No se encontró VM k3s-node-1"
    exit 1
fi

echo "VMID de k3s-node-1: $VMID"
qm status $VMID
echo ""

# 3. Verificar configuración de disco actual
echo "=== CONFIGURACIÓN DE DISCO ACTUAL ==="
qm config $VMID | grep -E "(scsi|virtio|sata|ide)" | head -5
echo ""

# 4. Verificar espacio disponible en storage
echo "=== ESPACIO DISPONIBLE EN STORAGE ==="
pvesm status
echo ""

# 5. Mostrar opciones de expansión
echo "=== OPCIONES DE EXPANSIÓN ==="
echo "1. Expandir disco existente (recomendado)"
echo "2. Agregar disco adicional"
echo "3. Migrar a storage con más espacio"
echo ""

# 6. Verificar si VM está corriendo
if qm status $VMID | grep -q "running"; then
    echo "⚠️  VM está corriendo. Se recomienda:"
    echo "   - Hacer snapshot antes de expandir"
    echo "   - O apagar VM temporalmente"
    echo ""
fi

echo "=== INSTRUCCIONES PARA EXPANSIÓN ==="
echo "Para expandir el disco de $VMID:"
echo "1. qm resize $VMID scsi0 +10G  # Agregar 10GB"
echo "2. qm resize $VMID scsi0 +20G  # Agregar 20GB"
echo "3. qm resize $VMID scsi0 +50G  # Agregar 50GB"
echo ""
echo "Luego en la VM:"
echo "1. fdisk /dev/sda  # Crear nueva partición"
echo "2. pvcreate /dev/sda2  # Si usa LVM"
echo "3. vgextend ubuntu-vg /dev/sda2"
echo "4. lvextend -l +100%FREE /dev/ubuntu-vg/ubuntu-lv"
echo "5. resize2fs /dev/ubuntu-vg/ubuntu-lv"
echo ""

echo "=== FIN DEL DIAGNÓSTICO ==="
