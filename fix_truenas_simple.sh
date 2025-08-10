#!/bin/bash

# Script simple para configurar TrueNAS y evitar que se llene el disco del sistema

TRUENAS_HOST="192.168.1.20"
TRUENAS_USER="truenas_admin"
TRUENAS_PASS="Constantinopl4"

echo "🔧 Configurando TrueNAS para evitar problemas de espacio..."

# 1. Verificar el estado actual
echo "📊 Estado actual de los pools:"
curl -k -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  "https://${TRUENAS_HOST}/api/v2.0/pool" | jq '.[] | {name: .name, free: .free_str, allocated: .allocated_str}'

# 2. Configurar el system dataset para usar el pool de almacenamiento
echo "⚙️ Configurando system dataset..."
curl -k -X PUT -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"pool": "homelab-storage", "basename": "homelab-storage/.system"}' \
  "https://${TRUENAS_HOST}/api/v2.0/systemdataset"

# 3. Configurar logs para que no se acumulen
echo "📝 Configurando logs del sistema..."
curl -k -X PUT -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"syslogserver": "", "syslog_transport": "UDP", "syslog_audit": false, "sysloglevel": "F_WARN"}' \
  "https://${TRUENAS_HOST}/api/v2.0/system/advanced"

# 4. Crear un dataset específico para logs del sistema
echo "📁 Creando dataset para logs del sistema..."
curl -k -X POST -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"name": "homelab-storage/system-logs", "type": "FILESYSTEM"}' \
  "https://${TRUENAS_HOST}/api/v2.0/pool/dataset"

# 5. Configurar cuotas para evitar que se llene el disco del sistema
echo "📏 Configurando cuotas de seguridad..."
curl -k -X PUT -H "Content-Type: application/json" \
  -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  -d '{"refquota": "1G"}' \
  "https://${TRUENAS_HOST}/api/v2.0/pool/dataset/homelab-storage%2F.system"

# 6. Verificar el estado final
echo "✅ Verificando configuración final..."
curl -k -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  "https://${TRUENAS_HOST}/api/v2.0/systemdataset"

echo "🎉 Configuración completada!"
echo "📊 Estado final de los pools:"
curl -k -u "${TRUENAS_USER}:${TRUENAS_PASS}" \
  "https://${TRUENAS_HOST}/api/v2.0/pool" | jq '.[] | {name: .name, free: .free_str, allocated: .allocated_str}'

echo "💡 Recomendaciones:"
echo "1. Monitorea el espacio del disco del sistema regularmente"
echo "2. Considera aumentar el tamaño del disco del sistema si es necesario"
echo "3. Configura alertas de espacio en TrueNAS"
echo "4. Revisa los logs del sistema periódicamente"
