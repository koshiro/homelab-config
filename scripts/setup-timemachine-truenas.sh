#!/bin/bash
# Script para configurar el dataset de Time Machine en TrueNAS
# Ejecutar desde el servidor Proxmox o desde un nodo con acceso a la API de TrueNAS

set -e

# Cargar variables de entorno si existe .env
if [ -f ".env" ]; then
    source .env
fi

# Configuración - usar variables de entorno o valores por defecto
TRUENAS_HOST="${TRUENAS_HOST:-192.168.1.20}"
API_KEY="${TRUENAS_API_KEY:-}"
DATASET_NAME="${DATASET_NAME:-timemachine}"
POOL_NAME="${POOL_NAME:-homelab-storage}"

# Verificar que la API key esté configurada
if [ -z "$API_KEY" ]; then
    echo "❌ Error: TRUENAS_API_KEY no está configurada"
    echo "📝 Crea un archivo .env con:"
    echo "   TRUENAS_API_KEY=tu_api_key_aqui"
    echo "   TRUENAS_HOST=192.168.1.20"
    echo "   DATASET_NAME=timemachine"
    echo "   POOL_NAME=homelab-storage"
    exit 1
fi

echo "🔧 Configurando Time Machine en TrueNAS..."
echo "📍 Host: ${TRUENAS_HOST}"
echo "📁 Dataset: ${DATASET_NAME}"
echo "💾 Pool: ${POOL_NAME}"

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
  
  # Generar contraseña aleatoria si no está configurada
  TIMEMACHINE_PASSWORD="${TIMEMACHINE_PASSWORD:-$(openssl rand -base64 12)}"
  
  USER_RESPONSE=$(curl -s -X POST \
    -H "Authorization: Bearer ${API_KEY}" \
    -H "Content-Type: application/json" \
    -d "{
      \"username\": \"timemachine\",
      \"full_name\": \"Time Machine User\",
      \"password\": \"${TIMEMACHINE_PASSWORD}\",
      \"uid\": 1000,
      \"group\": 100
    }" \
    "http://${TRUENAS_HOST}/api/v2.0/user")
  
  if echo "$USER_RESPONSE" | grep -q "error\|Error"; then
    echo "❌ Error creando usuario: $USER_RESPONSE"
    exit 1
  else
    echo "✅ Usuario timemachine creado exitosamente"
    echo "🔑 Contraseña generada: ${TIMEMACHINE_PASSWORD}"
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
if [ -n "$TIMEMACHINE_PASSWORD" ]; then
  echo "🔑 Contraseña: ${TIMEMACHINE_PASSWORD}"
fi
echo ""
echo "🚀 Ahora puedes desplegar el servicio en Kubernetes con:"
echo "   kubectl apply -k cluster/timemachine-smb/"
echo ""
echo "📋 Para verificar la configuración:"
echo "   kubectl get pods -n timemachine-smb"
echo "   kubectl get svc -n timemachine-smb"
echo ""
echo "💡 Recuerda guardar la contraseña del usuario timemachine en un lugar seguro"
