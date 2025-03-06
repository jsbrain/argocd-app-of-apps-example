#!/bin/bash
set -e

# Check for required tool: kubectl.
if ! command -v kubectl &>/dev/null; then
  echo "Error: kubectl is not installed."
  exit 1
fi

# Extract the ArgoCD admin password from the initial secret.
echo "Extracting ArgoCD admin password..."
ADMIN_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d)

if [ -z "$ADMIN_PASSWORD" ]; then
  echo "Error: Could not retrieve the admin password."
  exit 1
fi

echo "ArgoCD admin password: $ADMIN_PASSWORD"

# Forward port 8080 on localhost to the ArgoCD server.
echo "Starting port-forward to ArgoCD server (https://localhost:8080)..."
kubectl port-forward svc/argocd-server -n argocd 8080:443
