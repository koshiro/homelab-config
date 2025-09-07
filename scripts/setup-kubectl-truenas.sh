#!/bin/bash
# Script para configurar kubectl en TrueNAS
# Ejecutar desde TrueNAS

set -e

echo "=== Configurando kubectl en TrueNAS ==="

# Crear directorio .kube
mkdir -p /root/.kube

# Verificar si ya existe un kubeconfig
if [ -f "/root/.kube/config" ]; then
    echo "⚠️  Ya existe un archivo kubeconfig en /root/.kube/config"
    echo "¿Deseas sobrescribirlo? (y/N)"
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        echo "Configuración cancelada"
        exit 0
    fi
fi

# Obtener la IP del master del cluster
echo "Ingresa la IP del master del cluster (pibot):"
read -r MASTER_IP

if [ -z "${MASTER_IP}" ]; then
    echo "ERROR: Debes proporcionar la IP del master"
    exit 1
fi

# Crear kubeconfig básico
cat > /root/.kube/config << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://${MASTER_IP}:6443
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

echo "✅ Archivo kubeconfig creado en /root/.kube/config"

# Verificar conectividad
echo "Verificando conectividad al cluster..."
if kubectl get nodes > /dev/null 2>&1; then
    echo "✅ Conectividad al cluster verificada"
    echo "Nodos disponibles:"
    kubectl get nodes
else
    echo "❌ No se pudo conectar al cluster"
    echo "Verifica que:"
    echo "1. La IP del master sea correcta: ${MASTER_IP}"
    echo "2. El cluster esté funcionando"
    echo "3. No haya firewall bloqueando el puerto 6443"
    echo ""
    echo "Para obtener el token de autenticación, ejecuta en el master:"
    echo "kubectl -n kube-system describe secret \$(kubectl -n kube-system get secret | grep admin-user | awk '{print \$1}')"
fi

echo ""
echo "=== Configuración de kubectl completada ==="
echo "Archivo de configuración: /root/.kube/config"
echo "Para probar la conexión: kubectl get nodes"
