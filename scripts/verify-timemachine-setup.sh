#!/bin/bash
# Script para verificar la configuración de Time Machine en TrueNAS

set -e

# Configuración
TRUENAS_HOST="192.168.1.20"
API_KEY="1-W3MgqZZFNYGPVYIHWKLtaXEuWFvkRkbeUi3dHAGUlAlj5dwEzI5cRcG9eCHxSjpV"
DATASET_NAME="timemachine"
POOL_NAME="homelab-storage"

echo "🔍 Verificando configuración de Time Machine en TrueNAS..."
echo ""

# 1. Verificar dataset
echo "📁 Verificando dataset..."
DATASET_INFO=$(curl -s -H "Authorization: Bearer ${API_KEY}" \
  "http://${TRUENAS_HOST}/api/v2.0/pool/dataset" | \
  jq -r '.[] | select(.name | contains("timemachine"))')

if [ -n "$DATASET_INFO" ]; then
  DATASET_NAME_FULL=$(echo "$DATASET_INFO" | jq -r '.name')
  DATASET_PATH=$(echo "$DATASET_INFO" | jq -r '.mountpoint')
  DATASET_COMPRESSION=$(echo "$DATASET_INFO" | jq -r '.compression.value')
  DATASET_ATIME=$(echo "$DATASET_INFO" | jq -r '.atime.value')
  
  echo "✅ Dataset encontrado:"
  echo "   📁 Nombre: $DATASET_NAME_FULL"
  echo "   🗂️  Ruta: $DATASET_PATH"
  echo "   🗜️  Compresión: $DATASET_COMPRESSION"
  echo "   ⏰ Atime: $DATASET_ATIME"
else
  echo "❌ Dataset no encontrado"
  exit 1
fi

echo ""

# 2. Verificar usuario
echo "👤 Verificando usuario timemachine..."
USER_INFO=$(curl -s -H "Authorization: Bearer ${API_KEY}" \
  "http://${TRUENAS_HOST}/api/v2.0/user" | \
  jq -r '.[] | select(.username == "timemachine")')

if [ -n "$USER_INFO" ]; then
  USERNAME=$(echo "$USER_INFO" | jq -r '.username')
  USER_UID=$(echo "$USER_INFO" | jq -r '.uid')
  USER_GROUP=$(echo "$USER_INFO" | jq -r '.group.bsdgrp_group')
  
  echo "✅ Usuario encontrado:"
  echo "   👤 Usuario: $USERNAME"
  echo "   🆔 UID: $USER_UID"
  echo "   👥 Grupo: $USER_GROUP"
else
  echo "❌ Usuario timemachine no encontrado"
  exit 1
fi

echo ""

# 3. Verificar share NFS
echo "🌐 Verificando share NFS..."
NFS_INFO=$(curl -s -H "Authorization: Bearer ${API_KEY}" \
  "http://${TRUENAS_HOST}/api/v2.0/sharing/nfs" | \
  jq -r '.[] | select(.path | contains("timemachine"))')

if [ -n "$NFS_INFO" ]; then
  NFS_PATH=$(echo "$NFS_INFO" | jq -r '.path')
  NFS_COMMENT=$(echo "$NFS_INFO" | jq -r '.comment')
  NFS_ENABLED=$(echo "$NFS_INFO" | jq -r '.enabled')
  NFS_RO=$(echo "$NFS_INFO" | jq -r '.ro')
  NFS_MAPROOT_USER=$(echo "$NFS_INFO" | jq -r '.maproot_user')
  NFS_MAPROOT_GROUP=$(echo "$NFS_INFO" | jq -r '.maproot_group')
  
  echo "✅ Share NFS encontrado:"
  echo "   🌐 Ruta: $NFS_PATH"
  echo "   💬 Comentario: $NFS_COMMENT"
  echo "   ✅ Habilitado: $NFS_ENABLED"
  echo "   📖 Solo lectura: $NFS_RO"
  echo "   👤 Usuario root: $NFS_MAPROOT_USER"
  echo "   👥 Grupo root: $NFS_MAPROOT_GROUP"
else
  echo "❌ Share NFS no encontrado"
  exit 1
fi

echo ""

# 4. Verificar conectividad NFS
echo "🔌 Verificando conectividad NFS..."
if command -v showmount >/dev/null 2>&1; then
  NFS_EXPORTS=$(showmount -e 192.168.1.20 2>/dev/null | grep timemachine || echo "No encontrado")
  if [ "$NFS_EXPORTS" != "No encontrado" ]; then
    echo "✅ Export NFS accesible:"
    echo "   📡 $NFS_EXPORTS"
  else
    echo "⚠️  Export NFS no accesible desde este host"
  fi
else
  echo "ℹ️  Comando showmount no disponible para verificar conectividad"
fi

echo ""

# 5. Verificar espacio disponible
echo "💾 Verificando espacio disponible..."
DATASET_AVAILABLE=$(echo "$DATASET_INFO" | jq -r '.available.parsed')
DATASET_USED=$(echo "$DATASET_INFO" | jq -r '.used.parsed')

if [ -n "$DATASET_AVAILABLE" ] && [ -n "$DATASET_USED" ]; then
  echo "✅ Espacio del dataset:"
  echo "   📊 Disponible: $DATASET_AVAILABLE"
  echo "   📊 Usado: $DATASET_USED"
fi

echo ""
echo "🎉 Verificación completada exitosamente!"
echo ""
echo "📋 Próximos pasos:"
echo "   1. Desplegar el servicio en Kubernetes:"
echo "      kubectl apply -k cluster/timemachine/"
echo ""
echo "   2. Verificar el despliegue:"
echo "      kubectl get pods -n timemachine"
echo "      kubectl get svc -n timemachine"
echo ""
echo "   3. Configurar Time Machine en macOS:"
echo "      - Conectar a afp://tm.danielriquelme.cl"
echo "      - Usuario: timemachine"
echo "      - Contraseña: TimeMachine2024!"


