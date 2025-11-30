#!/bin/bash
# Scripts/verify-cluster-sync.sh
# Verifies that the local repository configuration matches the actual cluster state.

set -e

# Colors
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CLUSTER_DIR="./cluster"
REPORT_FILE="cluster-sync-report.txt"

echo "=== Cluster Synchronization Verification - $(date) ===" | tee $REPORT_FILE
echo "Scanning directory: $CLUSTER_DIR" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE

# Find all YAML files excluding kustomization.yml and kustomization.yaml
# We also exclude hidden files and backup directories
FILES=$(find $CLUSTER_DIR -type f \( -name "*.yml" -o -name "*.yaml" \) \
    -not -name "kustomization.yml" \
    -not -name "kustomization.yaml" \
    -not -path "*/.*" \
    | sort)

SYNCED_COUNT=0
DIFF_COUNT=0
ERROR_COUNT=0

for file in $FILES; do
    # Check if it's a valid k8s resource (has apiVersion and kind)
    if ! grep -q "apiVersion:" "$file" || ! grep -q "kind:" "$file"; then
        continue
    fi

    echo -n "Checking $file ... "
    
    # Check if resource exists in cluster
    if ! kubectl get -f "$file" &> /dev/null; then
        echo -e "${RED}NOT FOUND IN CLUSTER${NC}"
        echo "FILE: $file - Resource not found in cluster" >> $REPORT_FILE
        ((ERROR_COUNT++))
        continue
    fi

    # Check for differences
    # We use kubectl diff and capture output. 
    # kubectl diff returns 1 if differences found, 0 if clean.
    # We ignore "metadata.managedFields" and "status" implicitly via kubectl diff logic usually,
    # but sometimes it's noisy.
    
    if diff_output=$(kubectl diff -f "$file" 2>&1); then
        echo -e "${GREEN}SYNCED${NC}"
        ((SYNCED_COUNT++))
    else
        echo -e "${YELLOW}DIFF DETECTED${NC}"
        echo "---------------------------------------------------" >> $REPORT_FILE
        echo "FILE: $file" >> $REPORT_FILE
        echo "$diff_output" >> $REPORT_FILE
        echo "---------------------------------------------------" >> $REPORT_FILE
        ((DIFF_COUNT++))
    fi
done

echo "" | tee -a $REPORT_FILE
echo "=== Summary ===" | tee -a $REPORT_FILE
echo "Synced files: $SYNCED_COUNT" | tee -a $REPORT_FILE
echo "Files with differences: $DIFF_COUNT" | tee -a $REPORT_FILE
echo "Resources not found in cluster: $ERROR_COUNT" | tee -a $REPORT_FILE
echo "" | tee -a $REPORT_FILE
echo "Detailed report saved to: $REPORT_FILE"

