#!/bin/bash
# Implementar NFS Monitor DaemonSet
# Basado en: docs/RESILIENCIA-POST-APAGON-ANALISIS.md

set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=====================================${NC}"
echo -e "${GREEN}Implementando NFS Monitor DaemonSet${NC}"
echo -e "${GREEN}=====================================${NC}"
echo ""

echo -e "${YELLOW}Aplicando NFS Monitor DaemonSet...${NC}"

kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: DaemonSet
metadata:
  name: nfs-monitor
  namespace: kube-system
  labels:
    app: nfs-monitor
spec:
  selector:
    matchLabels:
      app: nfs-monitor
  template:
    metadata:
      labels:
        app: nfs-monitor
    spec:
      hostNetwork: true
      hostPID: true
      tolerations:
      - operator: Exists
      containers:
      - name: monitor
        image: alpine:3.20
        command:
        - sh
        - -c
        - |
          apk add --no-cache nfs-utils util-linux coreutils bash
          echo "✅ NFS Monitor iniciado en $(hostname)"
          
          while true; do
            # Verificar si NFS está montado
            if ! mount | grep -q "k8s-media-library"; then
              echo "⚠️  WARNING [$(date)]: NFS no montado en $(hostname), intentando remontar..."
              mkdir -p /mnt/k8s-media-library
              if mount -t nfs -o hard,nfsvers=4.2,noatime,nodiratime,rsize=1048576,wsize=1048576,tcp,nconnect=8 192.168.1.20:/mnt/homelab-storage/k8s-media-library /mnt/k8s-media-library; then
                echo "✅ NFS remontado exitosamente en $(hostname)"
              else
                echo "❌ ERROR [$(date)]: No se pudo remontar NFS en $(hostname)"
              fi
            else
              # Verificar que sea accesible (no stale)
              if timeout 5 ls /mnt/k8s-media-library >/dev/null 2>&1; then
                echo "✅ NFS OK en $(hostname) - $(date)"
              else
                echo "⚠️  WARNING [$(date)]: NFS stale en $(hostname), forzando remount..."
                umount -f /mnt/k8s-media-library 2>/dev/null || true
                sleep 2
                if mount -t nfs -o hard,nfsvers=4.2,noatime,nodiratime,rsize=1048576,wsize=1048576,tcp,nconnect=8 192.168.1.20:/mnt/homelab-storage/k8s-media-library /mnt/k8s-media-library; then
                  echo "✅ NFS remontado después de stale en $(hostname)"
                else
                  echo "❌ ERROR [$(date)]: No se pudo remontar NFS stale en $(hostname)"
                fi
              fi
            fi
            sleep 30
          done
        securityContext:
          privileged: true
        volumeMounts:
        - name: host-mount
          mountPath: /mnt
          mountPropagation: Bidirectional
      volumes:
      - name: host-mount
        hostPath:
          path: /mnt
          type: Directory
EOF

echo ""
echo -e "${GREEN}✓ NFS Monitor DaemonSet aplicado${NC}"
echo ""
echo -e "${YELLOW}Verificando estado...${NC}"
kubectl get daemonset -n kube-system nfs-monitor
echo ""
echo -e "${YELLOW}Pods del monitor:${NC}"
kubectl get pods -n kube-system -l app=nfs-monitor
echo ""
echo -e "${YELLOW}Para ver logs en tiempo real:${NC}"
echo "kubectl logs -n kube-system -l app=nfs-monitor -f"





