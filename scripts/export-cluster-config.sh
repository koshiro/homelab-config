#!/bin/bash
# scripts/export-cluster-config.sh
# Exports all cluster resources to cluster-export/ organized by namespace and kind.

set -e

EXPORT_DIR="./cluster-export"
DATE=$(date +%Y%m%d-%H%M)
LATEST_DIR="${EXPORT_DIR}/latest"

echo "=== Exporting Cluster Configuration - $DATE ==="
echo "Export directory: $LATEST_DIR"

mkdir -p "$LATEST_DIR"

# Get all namespaces
NAMESPACES=$(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}')

for ns in $NAMESPACES; do
    echo "Processing namespace: $ns"
    mkdir -p "${LATEST_DIR}/${ns}"
    
    # Get all resources in namespace
    # We focus on common resources we manage: Deployment, Service, PVC, Ingress, NetworkPolicy, ConfigMap, Secret, StatefulSet, DaemonSet
    # You can extend this list.
    RESOURCES="deployments services persistentvolumeclaims ingress networkpolicies configmaps secrets statefulsets daemonsets"
    
    for r in $RESOURCES; do
        mkdir -p "${LATEST_DIR}/${ns}/${r}"
        
        # Get list of resources of this type
        ITEMS=$(kubectl get "$r" -n "$ns" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
        
        for item in $ITEMS; do
            # Export to YAML
            # We use --export is deprecated, so we just get -o yaml and maybe clean up later if needed.
            # But for raw export, keeping metadata is fine to see status.
            kubectl get "$r" "$item" -n "$ns" -o yaml > "${LATEST_DIR}/${ns}/${r}/${item}.yaml"
        done
    done
done

# Export cluster-wide resources
echo "Processing cluster-wide resources"
CLUSTER_RESOURCES="nodes persistentvolumes storageclasses namespaces"
mkdir -p "${LATEST_DIR}/_cluster"

for r in $CLUSTER_RESOURCES; do
    mkdir -p "${LATEST_DIR}/_cluster/${r}"
    ITEMS=$(kubectl get "$r" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null || true)
    for item in $ITEMS; do
        kubectl get "$r" "$item" -o yaml > "${LATEST_DIR}/_cluster/${r}/${item}.yaml"
    done
done

# Generate checksums
echo "Generating checksums..."
find "$LATEST_DIR" -type f -name "*.yaml" -exec md5sum {} \; > "${LATEST_DIR}/checksums.md5"

echo "=== Export Completed ==="
echo "Location: $LATEST_DIR"

