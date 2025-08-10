#!/bin/bash

# Script para configurar TrueNAS para usar datasets específicos para logs
# y evitar que se llene el disco del sistema

TRUENAS_HOST="192.168.1.20"
TRUENAS_USER="truenas_admin"
TRUENAS_PASS="Constantinopl4"

echo "🔧 Configurando logs del sistema en TrueNAS..."

# 1. Crear directorios en los datasets del sistema
echo "📁 Creando directorios de logs..."
curl -k -X POST -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"path": "/mnt/homelab-storage/system-logs/var/log"}' \
  "https://${TRUENAS_HOST}/api/v2.0/filesystem/mkdir"

curl -k -X POST -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"path": "/mnt/homelab-storage/system-temp/var/tmp"}' \
  "https://${TRUENAS_HOST}/api/v2.0/filesystem/mkdir"

curl -k -X POST -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"path": "/mnt/homelab-storage/system-cache/var/cache"}' \
  "https://${TRUENAS_HOST}/api/v2.0/filesystem/mkdir"

# 2. Configurar permisos para los directorios
echo "🔐 Configurando permisos..."
for dir in "system-logs/var/log" "system-temp/var/tmp" "system-cache/var/cache"; do
  curl -k -X POST -H "Content-Type: application/json" \
    -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
    -d '{"path": "/mnt/homelab-storage/'${dir}'", "mode": "755", "user": "root", "group": "wheel"}' \
    "https://${TRUENAS_HOST}/api/v2.0/filesystem/setperm"
done

# 3. Configurar el system dataset para usar el pool de almacenamiento
echo "⚙️ Configurando system dataset..."
curl -k -X PUT -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"pool": "homelab-storage", "basename": "homelab-storage/.system"}' \
  "https://${TRUENAS_HOST}/api/v2.0/systemdataset"

# 4. Configurar variables de entorno para logs
echo "🌍 Configurando variables de entorno..."
curl -k -X PUT -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"syslogserver": "", "syslog_transport": "UDP", "syslog_audit": false}' \
  "https://${TRUENAS_HOST}/api/v2.0/system/advanced"

# 5. Crear enlaces simbólicos para redirigir logs al pool de almacenamiento
echo "🔗 Creando enlaces simbólicos..."
curl -k -X POST -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"path": "/mnt/homelab-storage/system-logs/var/log", "target": "/var/log", "type": "SYMLINK"}' \
  "https://${TRUENAS_HOST}/api/v2.0/filesystem/symlink"

# 6. Verificar el estado final
echo "✅ Verificando configuración final..."
curl -k -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  "https://${TRUENAS_HOST}/api/v2.0/systemdataset"

echo "🎉 Configuración de logs completada!"
echo "📊 Estado de los pools:"
curl -k -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  "https://${TRUENAS_HOST}/api/v2.0/pool" | jq '.[] | {name: .name, free: .free_str, allocated: .allocated_str}'
