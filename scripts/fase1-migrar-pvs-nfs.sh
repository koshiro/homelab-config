#!/usr/bin/env bash
# Fase 1 (docs/ARQUITECTURA.md): recrea los PV NFS que apuntan a TrueNAS (192.168.1.20)
# para que apunten al NFS de Proxmox (192.168.1.100), conservando path, capacidad y PVC.
#
# Requisitos: homelab-storage importado en Proxmox con mountpoint /mnt/homelab-storage
# y las rutas exportadas en /etc/exports.d/. Las apps que usan esos PVC deben estar en 0 réplicas.
#
# Uso: ./scripts/fase1-migrar-pvs-nfs.sh            # muestra lo que haría
#      ./scripts/fase1-migrar-pvs-nfs.sh --aplicar  # lo hace
set -euo pipefail

OLD=192.168.1.20
NEW=192.168.1.100
APPLY=0
[[ "${1:-}" == "--aplicar" ]] && APPLY=1
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

pvs=$(kubectl get pv -o json | python3 -c "
import json,sys
for pv in json.load(sys.stdin)['items']:
    if (pv['spec'].get('nfs') or {}).get('server') == '$OLD':
        print(pv['metadata']['name'])")

[[ -z "$pvs" ]] && { echo "No hay PV apuntando a $OLD"; exit 0; }

for pv in $pvs; do
  kubectl get pv "$pv" -o json > "$WORK/$pv.json"
  read -r ns pvc path < <(python3 -c "
import json; d=json.load(open('$WORK/$pv.json')); c=d['spec'].get('claimRef') or {}
print(c.get('namespace','-'), c.get('name','-'), d['spec']['nfs']['path'])")
  echo "== $pv  ($ns/$pvc)  $OLD:$path -> $NEW:$path"

  # Pods que usan el PVC: deben estar detenidos
  if [[ "$pvc" != "-" ]]; then
    users=$(kubectl -n "$ns" get pods -o json | python3 -c "
import json,sys
for p in json.load(sys.stdin)['items']:
    for v in p['spec'].get('volumes',[]):
        if (v.get('persistentVolumeClaim') or {}).get('claimName') == '$pvc': print(p['metadata']['name'])")
    if [[ -n "$users" ]]; then
      echo "   ⚠️  En uso por: $users — escalar a 0 antes. Se omite."; continue
    fi
    kubectl -n "$ns" get pvc "$pvc" -o json > "$WORK/$pv.pvc.json"
  fi

  # PV nuevo: mismo spec, servidor nuevo, sin estado ni claimRef
  python3 - "$WORK/$pv.json" "$NEW" > "$WORK/$pv.new.json" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1])); m=d['metadata']
d['metadata']={k:m[k] for k in ('name','labels','annotations') if k in m}
d['metadata'].get('annotations',{}).pop('pv.kubernetes.io/bound-by-controller',None)
d['metadata'].get('annotations',{}).pop('kubectl.kubernetes.io/last-applied-configuration',None)
d['spec']['nfs']['server']=sys.argv[2]; d['spec'].pop('claimRef',None); d.pop('status',None)
print(json.dumps(d))
EOF
  if [[ -f "$WORK/$pv.pvc.json" ]]; then
    python3 - "$WORK/$pv.pvc.json" "$pv" > "$WORK/$pv.pvc.new.json" <<'EOF'
import json,sys
d=json.load(open(sys.argv[1])); m=d['metadata']
d['metadata']={k:m[k] for k in ('name','namespace','labels') if k in m}
d['spec']['volumeName']=sys.argv[2]; d.pop('status',None)
print(json.dumps(d))
EOF
  fi

  if [[ $APPLY -eq 1 ]]; then
    [[ -f "$WORK/$pv.pvc.json" ]] && kubectl -n "$ns" delete pvc "$pvc" --wait=true
    kubectl delete pv "$pv" --wait=true
    kubectl apply -f "$WORK/$pv.new.json"
    [[ -f "$WORK/$pv.pvc.new.json" ]] && kubectl apply -f "$WORK/$pv.pvc.new.json"
  fi
done

[[ $APPLY -eq 0 ]] && echo -e "\nSimulación. Ejecutar con --aplicar para recrear los PV."
exit 0
