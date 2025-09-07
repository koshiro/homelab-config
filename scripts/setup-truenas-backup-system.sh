#!/bin/bash
# Script maestro para configurar el sistema completo de respaldos en TrueNAS
# Ejecutar desde la máquina local

set -e

# Configuración
TRUENAS_IP="192.168.1.20"
TRUENAS_USER="root"
SCRIPT_DIR="scripts"

echo "=== Configurando Sistema Completo de Respaldo en TrueNAS ==="
echo "TrueNAS IP: ${TRUENAS_IP}"
echo "Usuario: ${TRUENAS_USER}"
echo ""

# Verificar conectividad a TrueNAS
echo "1. Verificando conectividad a TrueNAS..."
if ping -c 1 ${TRUENAS_IP} > /dev/null 2>&1; then
    echo "✅ TrueNAS es accesible"
else
    echo "❌ No se puede conectar a TrueNAS"
    exit 1
fi

# Verificar que existe la API key
if [ ! -f ".truenas-api-key" ]; then
    echo "❌ No se encontró el archivo .truenas-api-key"
    echo "Crea el archivo con tu API key de TrueNAS"
    exit 1
fi

echo "✅ API key encontrada"

# Desplegar scripts
echo ""
echo "2. Desplegando scripts a TrueNAS..."
if [ -f "${SCRIPT_DIR}/deploy-to-truenas.sh" ]; then
    chmod +x ${SCRIPT_DIR}/deploy-to-truenas.sh
    ./${SCRIPT_DIR}/deploy-to-truenas.sh
else
    echo "❌ No se encontró el script de despliegue"
    exit 1
fi

# Configurar kubectl en TrueNAS
echo ""
echo "3. Configurando kubectl en TrueNAS..."
echo "¿Deseas configurar kubectl en TrueNAS ahora? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    scp ${SCRIPT_DIR}/setup-kubectl-truenas.sh ${TRUENAS_USER}@${TRUENAS_IP}:/root/
    ssh ${TRUENAS_USER}@${TRUENAS_IP} "chmod +x /root/setup-kubectl-truenas.sh && /root/setup-kubectl-truenas.sh"
else
    echo "⚠️  Saltando configuración de kubectl"
    echo "Recuerda configurar kubectl manualmente antes de ejecutar los cronjobs"
fi

# Configurar cronjobs
echo ""
echo "4. Configurando cronjobs en TrueNAS..."
echo "¿Deseas configurar los cronjobs ahora? (y/N)"
read -r response
if [[ "$response" =~ ^[Yy]$ ]]; then
    ssh ${TRUENAS_USER}@${TRUENAS_IP} "chmod +x /root/scripts/setup-truenas-cronjobs.sh && /root/scripts/setup-truenas-cronjobs.sh"
else
    echo "⚠️  Saltando configuración de cronjobs"
    echo "Para configurar los cronjobs manualmente:"
    echo "ssh ${TRUENAS_USER}@${TRUENAS_IP} '/root/scripts/setup-truenas-cronjobs.sh'"
fi

# Verificar configuración
echo ""
echo "5. Verificando configuración..."
echo "Scripts desplegados:"
ssh ${TRUENAS_USER}@${TRUENAS_IP} "ls -la /root/scripts/"

echo ""
echo "Cronjobs configurados:"
ssh ${TRUENAS_USER}@${TRUENAS_IP} "curl -k -s -X GET \"https://${TRUENAS_IP}/api/v2.0/cronjob\" -H \"Authorization: Bearer \$(cat /root/.truenas-api-key)\" | jq '.[] | {id: .id, description: .description, enabled: .enabled}'"

echo ""
echo "=== Configuración Completada ==="
echo ""
echo "Resumen de lo configurado:"
echo "✅ Scripts desplegados en TrueNAS"
echo "✅ Directorios de respaldo creados"
echo "✅ Cronjobs configurados (si se seleccionó)"
echo ""
echo "Cronjobs configurados:"
echo "1. Respaldo diario de configuraciones de pods (03:00)"
echo "2. Respaldo diario de configuración del cluster (03:30)"
echo "3. Verificación diaria de salud del sistema (04:00)"
echo "4. Limpieza semanal de logs del sistema (02:00 domingos)"
echo "5. Verificación diaria de salud del ZFS (05:00)"
echo "6. Limpieza semanal de snapshots antiguos (01:00 domingos)"
echo "7. Verificación del estado del cluster cada 6 horas"
echo "8. Verificación de conectividad cada 4 horas"
echo "9. Limpieza diaria de archivos temporales (06:00)"
echo "10. Respaldo semanal de infraestructura (05:00 domingos)"
echo ""
echo "Para verificar el estado de los respaldos:"
echo "ssh ${TRUENAS_USER}@${TRUENAS_IP} 'ls -la /mnt/homelab-storage/backups/'"
echo ""
echo "Para ejecutar un respaldo manual:"
echo "ssh ${TRUENAS_USER}@${TRUENAS_IP} '/root/scripts/backup-pod-configs.sh'"
