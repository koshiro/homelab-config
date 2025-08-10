#!/bin/bash

# Script para configurar TrueNAS para usar el pool de almacenamiento
# en lugar del disco del sistema para logs y datos temporales

TRUENAS_HOST="192.168.1.20"
TRUENAS_USER="truenas_admin"
TRUENAS_PASS="Constantinopl4"

echo "🔧 Configurando TrueNAS para usar pool de almacenamiento..."

# 1. Crear dataset para logs del sistema
echo "📝 Creando dataset para logs del sistema..."
curl -k -X POST -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"name": "homelab-storage/system-logs", "type": "FILESYSTEM"}' \
  "https://${TRUENAS_HOST}/api/v2.0/pool/dataset"

# 2. Crear dataset para datos temporales del sistema
echo "📁 Creando dataset para datos temporales..."
curl -k -X POST -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"name": "homelab-storage/system-temp", "type": "FILESYSTEM"}' \
  "https://${TRUENAS_HOST}/api/v2.0/pool/dataset"

# 3. Crear dataset para cache del sistema
echo "💾 Creando dataset para cache del sistema..."
curl -k -X POST -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"name": "homelab-storage/system-cache", "type": "FILESYSTEM"}' \
  "https://${TRUENAS_HOST}/api/v2.0/pool/dataset"

# 4. Configurar permisos para los datasets del sistema
echo "🔐 Configurando permisos..."
for dataset in "system-logs" "system-temp" "system-cache"; do
  curl -k -X POST -H "Content-Type: application/json" \
    -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
    -d '{"path": "/mnt/homelab-storage/'${dataset}'", "mode": "755", "user": "root", "group": "wheel"}' \
    "https://${TRUENAS_HOST}/api/v2.0/filesystem/setperm"
done

# 5. Configurar el system dataset para usar el pool de almacenamiento
echo "⚙️ Configurando system dataset..."
curl -k -X PUT -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"pool": "homelab-storage", "basename": "homelab-storage/.system"}' \
  "https://${TRUENAS_HOST}/api/v2.0/systemdataset"

# 6. Limpiar logs antiguos del sistema
echo "🧹 Limpiando logs antiguos..."
curl -k -X POST -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"path": "/mnt/homelab-storage/system-logs", "options": {"recursive": true}}' \
  "https://${TRUENAS_HOST}/api/v2.0/filesystem/rmdir"

# 7. Verificar el estado final
echo "✅ Verificando configuración final..."
curl -k -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  "https://${TRUENAS_HOST}/api/v2.0/systemdataset"

echo "🎉 Configuración completada!"
echo "📊 Verificando espacio disponible..."
curl -k -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  "https://${TRUENAS_HOST}/api/v2.0/pool" | jq '.[] | {name: .name, free: .free_str, allocated: .allocated_str}'
