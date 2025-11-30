#!/bin/bash
# Script para verificar la configuración de containerd para NVIDIA en k3s-node-1
# Ejecutar en el nodo k3s-node-1 con: sudo bash verify-nvidia-containerd-config.sh

set -e

echo "🔍 Verificando configuración de containerd para NVIDIA en k3s-node-1"
echo "=================================================================="
echo ""

# 1. Verificar archivo de configuración de NVIDIA runtime
echo "1️⃣ Verificando archivo de configuración..."
if [ -f /etc/rancher/k3s/config.toml.d/nvidia.toml ]; then
    echo "✅ Archivo existe: /etc/rancher/k3s/config.toml.d/nvidia.toml"
    echo "📄 Contenido:"
    cat /etc/rancher/k3s/config.toml.d/nvidia.toml
    echo ""
else
    echo "❌ Archivo NO existe: /etc/rancher/k3s/config.toml.d/nvidia.toml"
    echo "⚠️  Esto puede ser la causa del problema!"
    echo ""
fi

# 2. Verificar directorio
echo "2️⃣ Verificando directorio de configuración..."
if [ -d /etc/rancher/k3s/config.toml.d ]; then
    echo "✅ Directorio existe"
    echo "📁 Contenido:"
    ls -la /etc/rancher/k3s/config.toml.d/
    echo ""
else
    echo "❌ Directorio NO existe: /etc/rancher/k3s/config.toml.d"
    echo ""
fi

# 3. Verificar nvidia-container-runtime
echo "3️⃣ Verificando nvidia-container-runtime..."
if [ -f /usr/bin/nvidia-container-runtime ]; then
    echo "✅ nvidia-container-runtime existe"
    echo "📋 Versión:"
    /usr/bin/nvidia-container-runtime --version 2>&1 || echo "No se pudo obtener versión"
    echo ""
else
    echo "❌ nvidia-container-runtime NO existe: /usr/bin/nvidia-container-runtime"
    echo ""
fi

# 4. Verificar driver NVIDIA en el host
echo "4️⃣ Verificando driver NVIDIA en el host..."
if command -v nvidia-smi &> /dev/null; then
    echo "✅ nvidia-smi disponible"
    echo "📋 Información del driver:"
    nvidia-smi --query-gpu=driver_version,name --format=csv,noheader
    echo ""
else
    echo "❌ nvidia-smi NO disponible en el host"
    echo ""
fi

# 5. Verificar template de containerd
echo "5️⃣ Verificando template de containerd..."
if [ -f /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl ]; then
    echo "✅ Template existe"
    echo "🔍 Buscando configuración NVIDIA:"
    grep -A 10 -i nvidia /var/lib/rancher/k3s/agent/etc/containerd/config.toml.tmpl || echo "No se encontró configuración NVIDIA en el template"
    echo ""
else
    echo "⚠️  Template no existe (puede ser normal si se usa config.toml.d)"
    echo ""
fi

# 6. Verificar logs de k3s-agent
echo "6️⃣ Verificando logs recientes de k3s-agent relacionados con NVIDIA..."
journalctl -u k3s-agent --no-pager -n 100 | grep -i nvidia | tail -20 || echo "No se encontraron logs relacionados con NVIDIA"
echo ""

# 7. Verificar estado del servicio
echo "7️⃣ Verificando estado del servicio k3s-agent..."
systemctl status k3s-agent --no-pager -l | head -20
echo ""

echo "=================================================================="
echo "✅ Verificación completada"
echo ""
echo "📝 Resumen:"
echo "  - Si el archivo /etc/rancher/k3s/config.toml.d/nvidia.toml NO existe,"
echo "    esa es probablemente la causa del problema."
echo "  - Si existe pero nvidia-smi falla en los pods, puede ser un problema"
echo "    del driver 570.195.03 (versión problemática conocida)."
echo ""

