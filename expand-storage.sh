#!/bin/bash
# Script para expandir almacenamiento de k3s-node-1
# Ejecutar en el nodo k3s-node-1

set -euo pipefail

echo "=== EXPANSIÓN DE ALMACENAMIENTO k3s-node-1 ==="
echo "Fecha: $(date)"
echo ""

# 1. Verificar estado actual
echo "=== ESTADO ACTUAL ==="
df -h /
echo ""

# 2. Verificar si hay espacio sin particionar
echo "=== DISPOSITIVOS DISPONIBLES ==="
lsblk
echo ""

# 3. Verificar si es LVM
echo "=== VERIFICANDO LVM ==="
if command -v pvs >/dev/null 2>&1; then
    echo "LVM detectado:"
    pvs
    vgs
    lvs
else
    echo "LVM no detectado - usando particiones estándar"
fi
echo ""

# 4. Verificar si hay espacio expandible
echo "=== VERIFICANDO ESPACIO EXPANDIBLE ==="
if [ -b /dev/sda ]; then
    echo "Disco principal: /dev/sda"
    fdisk -l /dev/sda 2>/dev/null || echo "No se puede acceder a fdisk"
elif [ -b /dev/nvme0n1 ]; then
    echo "Disco NVMe: /dev/nvme0n1"
    fdisk -l /dev/nvme0n1 2>/dev/null || echo "No se puede acceder a fdisk"
else
    echo "No se pudo identificar el disco principal"
fi
echo ""

# 5. Verificar espacio en /var/lib/containerd
echo "=== ANÁLISIS DE CONTENEDORES ==="
if [ -d /var/lib/containerd ]; then
    echo "Tamaño de /var/lib/containerd:"
    du -sh /var/lib/containerd/* 2>/dev/null | head -10
    echo ""
    echo "Imágenes más grandes:"
    du -sh /var/lib/containerd/* 2>/dev/null | sort -hr | head -5
else
    echo "/var/lib/containerd no accesible"
fi
echo ""

# 6. Recomendaciones
echo "=== RECOMENDACIONES ==="
echo "1. Si es una VM: Expandir el disco virtual en el hypervisor"
echo "2. Si es físico: Agregar disco adicional"
echo "3. Limpieza inmediata: Eliminar imágenes no utilizadas"
echo "4. Configurar garbage collection más agresivo"
echo ""

echo "=== FIN DEL DIAGNÓSTICO ==="
