#!/bin/bash
# Script para configurar el dataset de Time Machine en TrueNAS
# Ejecutar desde el servidor Proxmox o desde un nodo con acceso a la API de TrueNAS

set -e

# Configuración
TRUENAS_HOST="192.168.1.20"
API_KEY="1-W3MgqZZFNYGPVYIHWKLtaXEuWFvkRkbeUi3dHAGUlAlj5dwEzI5cRcG9eCHxSjpV"
DATASET_NAME="timemachine"
POOL_NAME="homelab-storage"

echo "🔧 Configurando Time Machine en TrueNAS..."

# 1. Crear el dataset para Time Machine
echo "📁 Creando dataset '${DATASET_NAME}' en pool '${POOL_NAME}'..."
DATASET_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"${POOL_NAME}/${DATASET_NAME}\",
    \"type\": \"FILESYSTEM\",
    \"compression\": \"LZ4\",
    \"atime\": \"OFF\"
  }" \
  "http://${TRUENAS_HOST}/api/v2.0/pool/dataset")

if echo "$DATASET_RESPONSE" | grep -q "error\|Error"; then
  echo "❌ Error creando dataset: $DATASET_RESPONSE"
  exit 1
else
  echo "✅ Dataset creado exitosamente"
fi

# 2. Crear usuario timemachine si no existe
echo "👤 Verificando usuario timemachine..."
USER_EXISTS=$(curl -s -H "Authorization: Bearer ${API_KEY}" \
  "http://${TRUENAS_HOST}/api/v2.0/user" | \
  jq -r '.[] | select(.username == "timemachine") | .username')

if [ -z "$USER_EXISTS" ]; then
  echo "👤 Creando usuario timemachine..."
  USER_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d '{
      "username": "timemachine",
      "full_name": "Time Machine User",
      "password": "TimeMachine2024!",
      "uid": 1000,
      "group": 100
    }' \
    "http://${TRUENAS_HOST}/api/v2.0/user")
  
  if echo "$USER_RESPONSE" | grep -q "error\|Error"; then
    echo "❌ Error creando usuario: $USER_RESPONSE"
    exit 1
  else
    echo "✅ Usuario timemachine creado exitosamente"
  fi
else
  echo "✅ Usuario timemachine ya existe"
fi

# 3. Crear share NFS para el dataset
echo "🌐 Creando share NFS..."
NFS_RESPONSE=$(curl -s -X POST \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{
    \"path\": \"/mnt/${POOL_NAME}/${DATASET_NAME}\",
    \"comment\": \"Time Machine Backup Storage\",
    \"ro\": false,
    \"maproot_user\": \"timemachine\",
    \"maproot_group\": \"users\",
    \"networks\": [\"192.168.1.0/24\", \"10.42.0.0/16\", \"10.43.0.0/16\"],
    \"hosts\": [],
    \"enabled\": true
  }" \
  "http://${TRUENAS_HOST}/api/v2.0/sharing/nfs")

if echo "$NFS_RESPONSE" | grep -q "error\|Error"; then
  echo "❌ Error creando share NFS: $NFS_RESPONSE"
  exit 1
else
  echo "✅ Share NFS creado exitosamente"
fi

echo ""
echo "✅ Configuración de Time Machine completada en TrueNAS!"
echo "📊 Dataset: ${POOL_NAME}/${DATASET_NAME}"
echo "🌐 Share NFS: /mnt/${POOL_NAME}/${DATASET_NAME}"
echo "🔑 Usuario: timemachine"
echo "🔑 Contraseña: TimeMachine2024!"
echo ""
echo "🚀 Ahora puedes desplegar el servicio en Kubernetes con:"
echo "   kubectl apply -k cluster/timemachine/"
echo ""
echo "📋 Para verificar la configuración:"
echo "   kubectl get pods -n timemachine"
echo "   kubectl get svc -n timemachine"
