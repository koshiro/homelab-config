#!/bin/bash
# Limpieza de emergencia para liberar espacio en k3s-node-1
# Ejecutar en la VM k3s-node-1

set -euo pipefail

echo "=== LIMPIEZA DE EMERGENCIA k3s-node-1 ==="
echo "Fecha: $(date)"
echo ""

# 1. Verificar espacio actual
echo "=== ESPACIO ANTES DE LIMPIEZA ==="
df -h /
echo ""

# 2. Limpiar imágenes de contenedor
echo "=== LIMPIANDO IMÁGENES DE CONTENEDOR ==="
if command -v k3s >/dev/null 2>&1; then
    echo "Limpiando imágenes containerd..."
    k3s crictl images prune -f || echo "Error en prune"
    
    echo "Eliminando imágenes no utilizadas..."
    k3s crictl rmi \$(k3s crictl images -q) 2>/dev/null || echo "No hay imágenes para eliminar"
    
    echo "Limpiando contenedores detenidos..."
    k3s crictl rm \$(k3s crictl ps -a -q --filter "state=Exited") 2>/dev/null || echo "No hay contenedores para eliminar"
fi

# 3. Limpiar logs del sistema
echo "=== LIMPIANDO LOGS DEL SISTEMA ==="
journalctl --vacuum-time=3d || echo "Error en vacuum de journal"
find /var/log -name "*.log" -mtime +3 -delete 2>/dev/null || echo "Error en limpieza de logs"

# 4. Limpiar cache de paquetes
echo "=== LIMPIANDO CACHE DE PAQUETES ==="
apt-get clean || echo "Error en apt-get clean"
apt-get autoremove -y || echo "Error en autoremove"

# 5. Limpiar archivos temporales
echo "=== LIMPIANDO ARCHIVOS TEMPORALES ==="
rm -rf /tmp/* 2>/dev/null || echo "Error en limpieza de /tmp"
rm -rf /var/tmp/* 2>/dev/null || echo "Error en limpieza de /var/tmp"

# 6. Verificar espacio después de limpieza
echo "=== ESPACIO DESPUÉS DE LIMPIEZA ==="
df -h /
echo ""

# 7. Mostrar los directorios más grandes
echo "=== DIRECTORIOS MÁS GRANDES ==="
du -sh /var/lib/containerd/* 2>/dev/null | sort -hr | head -5 || echo "No se pudo acceder a containerd"

echo "=== LIMPIEZA COMPLETADA ==="
