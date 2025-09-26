#!/bin/bash
# Script para corregir el sistema de respaldos usando la API de TrueNAS
# Ejecutar desde la máquina local

set -e

# Configuración
TRUENAS_IP="192.168.1.20"
API_KEY_FILE="/Users/daniel/git/homelab-config/.truenas-api-key"
SCRIPT_DIR="/Users/daniel/git/homelab-config/scripts"

# Verificar que existe la API key
if [ ! -f "${API_KEY_FILE}" ]; then
    echo "ERROR: No se encontró el archivo de API key en ${API_KEY_FILE}"
    exit 1
fi

API_KEY=$(cat "${API_KEY_FILE}")

echo "=== Corrigiendo sistema de respaldos en TrueNAS ==="

# Función para hacer requests a la API
api_request() {
    local method=$1
    local endpoint=$2
    local data=$3
    
    if [ -n "${data}" ]; then
        curl -k -s -X "${method}" "https://${TRUENAS_IP}/api/v2.0/${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}" \
            -H "Content-Type: application/json" \
            -d "${data}"
    else
        curl -k -s -X "${method}" "https://${TRUENAS_IP}/api/v2.0/${endpoint}" \
            -H "Authorization: Bearer ${API_KEY}"
    fi
}

# Función para crear archivos en TrueNAS usando la API
create_file() {
    local file_path=$1
    local content=$2
    
    # Crear el archivo usando la API de TrueNAS
    api_request "POST" "filesystem/setperm" "{
        \"path\": \"${file_path}\",
        \"mode\": \"755\",
        \"user\": \"root\",
        \"group\": \"wheel\"
    }" > /dev/null
    
    # Escribir contenido al archivo
    echo "${content}" | api_request "POST" "filesystem/put" "{
        \"path\": \"${file_path}\",
        \"content\": \"$(echo "${content}" | base64 -w 0)\"
    }" > /dev/null
}

echo "1. Creando directorios necesarios..."

# Crear directorios de respaldo
api_request "POST" "filesystem/mkdir" '{"path": "/mnt/homelab-storage/backups/pod-configs"}' > /dev/null || true
api_request "POST" "filesystem/mkdir" '{"path": "/mnt/homelab-storage/backups/cluster-config"}' > /dev/null || true
api_request "POST" "filesystem/mkdir" '{"path": "/mnt/homelab-storage/backups/system-health"}' > /dev/null || true
api_request "POST" "filesystem/mkdir" '{"path": "/mnt/homelab-storage/backups/infrastructure"}' > /dev/null || true
api_request "POST" "filesystem/mkdir" '{"path": "/root/scripts"}' > /dev/null || true

echo "✅ Directorios creados"

echo ""
echo "2. Desplegando scripts de respaldo..."

# Leer y desplegar backup-pod-configs.sh
backup_pod_script=$(cat "${SCRIPT_DIR}/backup-pod-configs.sh")
create_file "/root/scripts/backup-pod-configs.sh" "${backup_pod_script}"

# Leer y desplegar backup-cluster-config.sh
backup_cluster_script=$(cat "${SCRIPT_DIR}/backup-cluster-config.sh")
create_file "/root/scripts/backup-cluster-config.sh" "${backup_cluster_script}"

# Leer y desplegar system-health-check.sh
health_check_script=$(cat "${SCRIPT_DIR}/system-health-check.sh")
create_file "/root/scripts/system-health-check.sh" "${health_check_script}"

echo "✅ Scripts desplegados"

echo ""
echo "3. Instalando kubectl en TrueNAS..."

# Crear script de instalación de kubectl
kubectl_install_script='#!/bin/bash
# Instalar kubectl en TrueNAS
set -e

echo "Instalando kubectl..."

# Descargar kubectl
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
chmod +x kubectl
mv kubectl /usr/local/bin/

# Crear directorio .kube
mkdir -p /root/.kube

# Crear kubeconfig básico
cat > /root/.kube/config << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://192.168.1.10:6443
    insecure-skip-tls-verify: true
  name: homelab-cluster
contexts:
- context:
    cluster: homelab-cluster
    user: admin
  name: homelab-context
current-context: homelab-context
users:
- name: admin
  user:
    token: ""
EOF

echo "kubectl instalado y configurado"
echo "NOTA: Necesitas configurar el token de autenticación manualmente"
'

create_file "/root/scripts/install-kubectl.sh" "${kubectl_install_script}"

# Ejecutar instalación de kubectl
echo "Ejecutando instalación de kubectl..."
api_request "POST" "cronjob" '{
    "command": "/root/scripts/install-kubectl.sh",
    "description": "Instalación de kubectl",
    "enabled": true,
    "schedule": {
        "minute": "*",
        "hour": "*",
        "dom": "*",
        "month": "*",
        "dow": "*"
    },
    "stderr": true,
    "stdout": true,
    "user": "root"
}' > /dev/null

echo "✅ kubectl instalado"

echo ""
echo "4. Creando script de diagnóstico mejorado..."

# Crear script de diagnóstico
diagnostic_script='#!/bin/bash
# Script de diagnóstico para el sistema de respaldos
set -e

echo "=== Diagnóstico del Sistema de Respaldos ==="
echo "Fecha: $(date)"
echo ""

echo "1. Verificando kubectl..."
if command -v kubectl > /dev/null 2>&1; then
    echo "✅ kubectl está instalado"
    kubectl version --client 2>/dev/null || echo "⚠️  kubectl instalado pero no funciona correctamente"
else
    echo "❌ kubectl no está instalado"
fi

echo ""
echo "2. Verificando conectividad al cluster..."
if kubectl get nodes > /dev/null 2>&1; then
    echo "✅ Conectividad al cluster OK"
    echo "Nodos disponibles:"
    kubectl get nodes
else
    echo "❌ No se puede conectar al cluster"
    echo "Verifica la configuración de kubeconfig en /root/.kube/config"
fi

echo ""
echo "3. Verificando pods de la ARR Suite..."
namespaces=("plex" "sonarr" "radarr" "bazarr" "prowlarr" "overseerr" "pingvin" "qbittorrent")

for ns in "${namespaces[@]}"; do
    echo -n "Namespace ${ns}: "
    if kubectl get pods -n "${ns}" > /dev/null 2>&1; then
        pod_count=$(kubectl get pods -n "${ns}" --no-headers | wc -l)
        running_count=$(kubectl get pods -n "${ns}" --field-selector=status.phase=Running --no-headers | wc -l)
        echo "✅ ${pod_count} pods total, ${running_count} ejecutándose"
        
        # Verificar labels
        for pod in $(kubectl get pods -n "${ns}" -o jsonpath="{.items[*].metadata.name}"); do
            labels=$(kubectl get pod "${pod}" -n "${ns}" -o jsonpath="{.metadata.labels.app}")
            echo "  Pod ${pod}: app=${labels}"
        done
    else
        echo "❌ No se puede acceder al namespace ${ns}"
    fi
done

echo ""
echo "4. Verificando directorios de respaldo..."
backup_dirs=("/mnt/homelab-storage/backups/pod-configs" "/mnt/homelab-storage/backups/cluster-config" "/mnt/homelab-storage/backups/system-health")

for dir in "${backup_dirs[@]}"; do
    if [ -d "${dir}" ]; then
        echo "✅ ${dir} existe"
        file_count=$(find "${dir}" -type f | wc -l)
        echo "  Archivos: ${file_count}"
    else
        echo "❌ ${dir} no existe"
    fi
done

echo ""
echo "5. Verificando scripts de respaldo..."
scripts=("/root/scripts/backup-pod-configs.sh" "/root/scripts/backup-cluster-config.sh" "/root/scripts/system-health-check.sh")

for script in "${scripts[@]}"; do
    if [ -f "${script}" ] && [ -x "${script}" ]; then
        echo "✅ ${script} existe y es ejecutable"
    else
        echo "❌ ${script} no existe o no es ejecutable"
    fi
done

echo ""
echo "6. Probando respaldo de un pod (Plex)..."
if kubectl get pods -n plex -l app=plex > /dev/null 2>&1; then
    pod_name=$(kubectl get pods -n plex -l app=plex -o jsonpath="{.items[0].metadata.name}")
    echo "Probando respaldo del pod: ${pod_name}"
    
    # Crear directorio de prueba
    mkdir -p /tmp/backup-test
    
    # Intentar crear respaldo
    if kubectl exec -n plex "${pod_name}" -- tar czf /tmp/test-backup.tar.gz /config > /dev/null 2>&1; then
        echo "✅ Respaldo de prueba exitoso"
        kubectl exec -n plex "${pod_name}" -- rm -f /tmp/test-backup.tar.gz
    else
        echo "❌ Error en respaldo de prueba"
    fi
else
    echo "❌ No se encontró pod de Plex para probar"
fi

echo ""
echo "=== Diagnóstico completado ==="
'

create_file "/root/scripts/diagnostic.sh" "${diagnostic_script}"

echo "✅ Script de diagnóstico creado"

echo ""
echo "5. Ejecutando diagnóstico..."

# Ejecutar diagnóstico
api_request "POST" "cronjob" '{
    "command": "/root/scripts/diagnostic.sh",
    "description": "Diagnóstico del sistema de respaldos",
    "enabled": true,
    "schedule": {
        "minute": "*",
        "hour": "*",
        "dom": "*",
        "month": "*",
        "dow": "*"
    },
    "stderr": true,
    "stdout": true,
    "user": "root"
}' > /dev/null

echo "✅ Diagnóstico ejecutado"

echo ""
echo "6. Actualizando cronjobs existentes..."

# Actualizar cronjob de respaldo de pods para que use el script correcto
api_request "PUT" "cronjob/id/4" '{
    "command": "/root/scripts/backup-pod-configs.sh",
    "description": "Respaldo diario de configuraciones de pods",
    "enabled": true,
    "schedule": {
        "minute": "0",
        "hour": "3",
        "dom": "*",
        "month": "*",
        "dow": "*"
    },
    "stderr": true,
    "stdout": true,
    "user": "root"
}' > /dev/null

echo "✅ Cronjobs actualizados"

echo ""
echo "=== Corrección completada ==="
echo ""
echo "Próximos pasos:"
echo "1. Verificar el diagnóstico ejecutando: curl -k -X GET \"https://${TRUENAS_IP}/api/v2.0/cronjob\" -H \"Authorization: Bearer ${API_KEY}\" | jq"
echo "2. Los respaldos se ejecutarán automáticamente a las 03:00"
echo "3. Para ejecutar respaldo manual: crear un cronjob temporal con el comando /root/scripts/backup-pod-configs.sh"
echo ""
echo "Si el problema persiste, verifica:"
echo "- La conectividad de red entre TrueNAS y el cluster"
echo "- La configuración de kubeconfig en TrueNAS"
echo "- Los labels de los pods (deben tener app=servicename)"
