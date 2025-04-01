#!/bin/bash
set -euo pipefail

# Check for prerequisites
if ! command -v kind >/dev/null 2>&1; then
  echo "Error: kind is not installed. Please install kind."
  exit 1
fi

if ! command -v kubectl >/dev/null 2>&1; then
  echo "Error: kubectl is not installed. Please install kubectl."
  exit 1
fi

# Variables
CLUSTER_NAME="argocd-cluster"
ARGOCD_NAMESPACE="argocd"
REPO_URL="https://github.com/jsbrain/argocd-app-of-apps-example.git"

# Step 1: Create a local Kind cluster
echo "Creating Kind cluster '${CLUSTER_NAME}'..."
kind create cluster --name "${CLUSTER_NAME}"

# --- START MetalLB Installation ---
echo "Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.7/config/manifests/metallb-native.yaml

echo "Waiting for MetalLB controller to become ready..."
kubectl -n metallb-system rollout status deploy/controller --timeout=120s

echo "Waiting for MetalLB speakers to become ready (may take a moment)..."
# Wait for the daemonset update to be observed and pods to start/become ready.
# A simple sleep is less robust but often sufficient for local kind setups.
sleep 15
kubectl wait --for=condition=ready pod -l app=metallb -n metallb-system --timeout=120s

echo "Applying MetalLB configuration (using manifests/metallb-config.yaml)..."
# Ensure this script is run from the repo root or adjust path.
kubectl apply -f manifests/metallb-config.yaml
echo "MetalLB setup complete."
# --- END MetalLB Installation ---

# Step 2: Install ArgoCD into the cluster
echo "Creating namespace ${ARGOCD_NAMESPACE}..."
kubectl create namespace ${ARGOCD_NAMESPACE} || true
echo "Installing ArgoCD..."
kubectl apply -n ${ARGOCD_NAMESPACE} -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml

# Wait for ArgoCD server deployment to be ready
echo "Waiting for ArgoCD server to become ready..."
kubectl -n ${ARGOCD_NAMESPACE} rollout status deploy/argocd-server --timeout=300s

# Step 3: Create the ArgoCD Project
echo "Applying AppProject manifest..."
kubectl apply -f bootstrap/project.yaml -n ${ARGOCD_NAMESPACE}

# Step 4: Deploy the Parent Application (App-of-Apps)
echo "Applying Parent Application manifest..."
kubectl apply -f bootstrap/app-of-apps.yaml -n ${ARGOCD_NAMESPACE}

# Step 5: Port-forward ArgoCD server for UI access (runs in background)
echo "Port-forwarding ArgoCD server to localhost:8080..."
kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443 &
PF_PID=$!

# Step 6: Retrieve the initial admin password
echo "Retrieving ArgoCD admin password..."
ADMIN_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD admin password: ${ADMIN_PASSWORD}"
echo "Access the ArgoCD UI at: https://localhost:8080 (login as admin)"

# Step 7: Wait for the Parent Application to sync
echo "Waiting for Parent Application (app-of-apps) to sync..."
while true; do
  STATUS=$(kubectl get application app-of-apps -n ${ARGOCD_NAMESPACE} -o jsonpath="{.status.sync.status}" 2>/dev/null || echo "NotFound")
  if [ "$STATUS" = "Synced" ]; then
    echo "Parent Application is Synced."
    break
  else
    echo "Current sync status: $STATUS. Waiting..."
    sleep 5
  fi
done

# --- START Show Service IPs ---
echo "---------------------------------------------------"
echo "Listing application services with LoadBalancer IPs..."
# Give apps a moment to potentially get IPs assigned after sync
sleep 5
kubectl get svc --all-namespaces -o wide | grep LoadBalancer | cat
echo "---------------------------------------------------"
# --- END Show Service IPs ---

echo "Bootstrap complete. Press Ctrl+C to stop port-forwarding when finished."
wait $PF_PID
