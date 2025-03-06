#!/bin/bash
set -euo pipefail

# Variables
CLUSTER_NAME="argocd-cluster"
ARGOCD_NAMESPACE="argocd"

# Step 1: Kill ArgoCD port-forward processes if running.
echo "Checking for running port-forward processes..."
PF_PIDS=$(pgrep -f "kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443" || true)
if [ -n "$PF_PIDS" ]; then
  echo "Killing port-forward processes: $PF_PIDS"
  kill $PF_PIDS
else
  echo "No port-forward processes found."
fi

# Step 2: Delete the Kind cluster.
echo "Deleting Kind cluster '${CLUSTER_NAME}'..."
kind delete cluster --name "${CLUSTER_NAME}"

echo "Cluster and associated resources have been successfully destroyed."
