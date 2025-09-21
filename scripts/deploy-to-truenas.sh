#!/bin/bash
# Script para desplegar scripts y configuraciones en TrueNAS
# Ejecutar desde la máquina local

set -e

# Configuración
TRUENAS_IP="192.168.1.20"
TRUENAS_USER="root"
SCRIPT_DIR="scripts"
TRUENAS_SCRIPT_DIR="/root/scripts"

echo "=== Desplegando scripts a TrueNAS ==="

# Verificar que los scripts existen
required_scripts=("backup-pod-configs.sh" "backup-cluster-config.sh" "system-health-check.sh" "setup-truenas-cronjobs.sh")

for script in "${required_scripts[@]}"; do
    if [ ! -f "${SCRIPT_DIR}/${script}" ]; then
        echo "ERROR: No se encontró el script ${script}"
        exit 1
    fi
done

echo "✅ Todos los scripts requeridos encontrados"

# Crear directorio en TrueNAS
echo "Creando directorio de scripts en TrueNAS..."
ssh ${TRUENAS_USER}@${TRUENAS_IP} "mkdir -p ${TRUENAS_SCRIPT_DIR}"

# Transferir scripts
echo "Transfiriendo scripts a TrueNAS..."
scp ${SCRIPT_DIR}/*.sh ${TRUENAS_USER}@${TRUENAS_IP}:${TRUENAS_SCRIPT_DIR}/

# Dar permisos de ejecución
echo "Configurando permisos de ejecución..."
ssh ${TRUENAS_USER}@${TRUENAS_IP} "chmod +x ${TRUENAS_SCRIPT_DIR}/*.sh"

# Crear directorios de respaldo
echo "Creando directorios de respaldo..."
ssh ${TRUENAS_USER}@${TRUENAS_IP} "mkdir -p /mnt/homelab-storage/backups/{pod-configs,cluster-config,system-health,infrastructure}"

# Verificar que kubectl está disponible
echo "Verificando configuración de kubectl..."
if ssh ${TRUENAS_USER}@${TRUENAS_IP} "kubectl version --client" > /dev/null 2>&1; then
    echo "✅ kubectl está disponible en TrueNAS"
else
    echo "⚠️  ADVERTENCIA: kubectl no está disponible en TrueNAS"
    echo "Necesitas configurar kubectl en TrueNAS para que los respaldos funcionen"
fi

# Verificar conectividad al cluster
echo "Verificando conectividad al cluster..."
if ssh ${TRUENAS_USER}@${TRUENAS_IP} "kubectl get nodes" > /dev/null 2>&1; then
    echo "✅ TrueNAS puede conectarse al cluster"
else
    echo "⚠️  ADVERTENCIA: TrueNAS no puede conectarse al cluster"
    echo "Necesitas configurar el kubeconfig en TrueNAS"
fi

echo ""
echo "=== Despliegue completado ==="
echo "Scripts desplegados en: ${TRUENAS_SCRIPT_DIR}"
echo ""
echo "Próximos pasos:"
echo "1. Configurar kubectl en TrueNAS si no está configurado"
echo "2. Ejecutar el script de configuración de cronjobs:"
echo "   ssh ${TRUENAS_USER}@${TRUENAS_IP} '${TRUENAS_SCRIPT_DIR}/setup-truenas-cronjobs.sh'"
echo "3. Verificar que los cronjobs se crearon correctamente"
echo ""
echo "Para verificar los cronjobs:"
echo "ssh ${TRUENAS_USER}@${TRUENAS_IP} 'curl -k -X GET \"https://${TRUENAS_IP}/api/v2.0/cronjob\" -H \"Authorization: Bearer \$(cat /root/.truenas-api-key)\" | jq'"
