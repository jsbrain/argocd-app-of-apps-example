#!/bin/bash
set -euo pipefail

# Variables (should match bootstrap-argocd.sh)
CLUSTER_NAME="argocd-cluster"
DOMAIN="localcluster"

# Step 1: Delete the Kind cluster
echo "Attempting to delete Kind cluster '${CLUSTER_NAME}'..."
if kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  kind delete cluster --name "${CLUSTER_NAME}"
  echo "Kind cluster '${CLUSTER_NAME}' deleted."
else
  echo "Kind cluster '${CLUSTER_NAME}' not found. Skipping deletion."
fi

# Step 2: Provide instructions for DNS Cleanup
OS_TYPE="$(uname -s)"

echo ""
echo "---------------------------------------------------"
echo "ACTION REQUIRED: Clean Up Local DNS Configuration"
echo "---------------------------------------------------"

if [[ "$OS_TYPE" == "Darwin" ]]; then
  # macOS Instructions
  RESOLVER_FILE="/etc/resolver/${DOMAIN}"
  echo "Detected macOS."
  echo "If you configured DNS using /etc/resolver/, remove the custom resolver file:"
  echo ""
  echo "  sudo rm ${RESOLVER_FILE}"
  echo ""
  echo "You might need to clear your DNS cache afterwards:"
  echo "  sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder"
  echo ""
elif [[ "$OS_TYPE" == "Linux" ]]; then
  # Linux/Ubuntu Instructions
  HOSTS_FILE="/etc/hosts"
  echo "Detected Linux."
  echo "If you modified your ${HOSTS_FILE} file, remove the entries pointing to the cluster IP."
  echo "Look for lines containing hostnames ending in '.${DOMAIN}'."
  echo ""
  echo "Example: Edit the file using 'sudo nano ${HOSTS_FILE}' and delete lines like:"
  echo "  X.X.X.X grafana.${DOMAIN} prometheus.${DOMAIN} ..." # Replace X.X.X.X with the actual IP
  echo ""
else
  # Fallback for other OS types
  echo "Detected OS: ${OS_TYPE}."
  echo "Please manually remove any DNS configuration you added for the '.${DOMAIN}' domain"
  echo "(e.g., entries in /etc/hosts or other system-specific DNS settings)."
fi

echo "---------------------------------------------------"

echo "Destroy script finished."
