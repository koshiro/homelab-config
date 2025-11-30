#!/bin/bash
# Script para revertir el driver NVIDIA de 570.x a 550.x
# Ejecutar en k3s-node-1 con: sudo bash revert-nvidia-driver-550.sh
# 
# ADVERTENCIA: Este script reiniciará el nodo

set -e

echo "🔄 Revertir driver NVIDIA de 570.x a 550.x"
echo "=========================================="
echo ""
echo "⚠️  ADVERTENCIA: Este script reiniciará el nodo k3s-node-1"
echo "⚠️  Asegúrate de que no hay trabajos críticos corriendo"
echo ""
read -p "¿Continuar? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "❌ Operación cancelada"
    exit 1
fi

echo ""
echo "📋 Paso 1: Verificar versión actual del driver..."
nvidia-smi --query-gpu=driver_version --format=csv,noheader || echo "No se pudo obtener versión"
echo ""

echo "📋 Paso 2: Desinstalar driver 570.x..."
apt-get remove -y nvidia-driver-570* || true
apt-get autoremove -y || true
echo ""

echo "📋 Paso 3: Limpiar configuración antigua..."
apt-get purge -y nvidia-* || true
apt-get autoremove -y || true
apt-get autoclean || true
echo ""

echo "📋 Paso 4: Instalar driver 550.x..."
# Instalar versión específica estable de 550.x
apt-get update
apt-get install -y nvidia-driver-550
echo ""

echo "📋 Paso 5: Verificar instalación..."
dpkg -l | grep nvidia-driver-550 || echo "⚠️  No se encontró nvidia-driver-550 instalado"
echo ""

echo "📋 Paso 6: Reiniciar el nodo..."
echo "⚠️  El nodo se reiniciará en 10 segundos..."
sleep 10
reboot

