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
KIND_CONFIG_FILE="kind-config.yaml"

# Step 1: Create a local Kind cluster if it doesn't exist
if ! kind get clusters | grep -q "^${CLUSTER_NAME}$"; then
  echo "Creating Kind cluster '${CLUSTER_NAME}' with config ${KIND_CONFIG_FILE}..."
  kind create cluster --name "${CLUSTER_NAME}" --config "${KIND_CONFIG_FILE}"
else
  echo "Kind cluster '${CLUSTER_NAME}' already exists. Skipping creation."
fi

# Switch kubectl context to the kind cluster (important if script is re-run)
kubectl config use-context "kind-${CLUSTER_NAME}"

# Label worker nodes for Ingress Controller compatibility
# The Kind Ingress manifest expects nodes with label ingress-ready=true
echo "Labeling worker nodes for ingress readiness..."
kubectl label node "${CLUSTER_NAME}-worker" ingress-ready=true --overwrite=true || echo "Label already exists or node not found - proceeding"
kubectl label node "${CLUSTER_NAME}-worker2" ingress-ready=true --overwrite=true || echo "Label already exists or node not found - proceeding"

# --- START MetalLB Installation ---
echo "Installing MetalLB..."
kubectl apply -f https://raw.githubusercontent.com/metallb/metallb/v0.14.9/config/manifests/metallb-native.yaml

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

# --- START Nginx Ingress Controller Installation ---
echo "Installing Nginx Ingress Controller..."
# Use the generic 'cloud' deployment manifest which creates a LoadBalancer service
# instead of the 'kind' manifest which uses NodePort.
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.12.1/deploy/static/provider/cloud/deploy.yaml

echo "Waiting for Nginx Ingress controller admission webhook to become ready..."
# The webhook is crucial for Ingress object validation and needs ~2m in Kind
kubectl wait --namespace ingress-nginx \
  --for=condition=ready pod \
  --selector=app.kubernetes.io/component=controller \
  --timeout=300s

echo "Waiting for Nginx Ingress controller deployment to become ready..."
kubectl -n ingress-nginx rollout status deploy/ingress-nginx-controller --timeout=120s

# Give it a few seconds for the LoadBalancer IP to be assigned by MetalLB
echo "Waiting for Ingress LoadBalancer IP..."
sleep 10
INGRESS_IP=""
while [ -z "$INGRESS_IP" ]; do
  echo "Attempting to get Ingress IP..."
  INGRESS_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
  [ -z "$INGRESS_IP" ] && sleep 5
done
echo "Nginx Ingress Controller IP: ${INGRESS_IP}"
echo "Nginx Ingress Controller setup complete."
# --- END Nginx Ingress Controller Installation ---

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

# Step 5: Retrieve the initial admin password
echo "Retrieving ArgoCD admin password (may fail if changed)..."
ADMIN_PASSWORD=$(kubectl -n ${ARGOCD_NAMESPACE} get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" 2>/dev/null | base64 -d || echo "(could not retrieve initial secret - password may have been changed)")
echo "ArgoCD admin user: admin"
echo "ArgoCD initial admin password: ${ADMIN_PASSWORD}"

# Step 6: Instructions for UI Access
echo ""
echo "---------------------------------------------------"
echo "Argo CD UI Access Instructions"
echo "---------------------------------------------------"
echo "To access the Argo CD UI, run the following port-forward command in a separate terminal:"
echo "  kubectl port-forward svc/argocd-server -n ${ARGOCD_NAMESPACE} 8080:443"
echo "Then, open https://localhost:8080 in your browser."
echo "Login with username 'admin' and the password retrieved above."
echo "---------------------------------------------------"

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

# --- Instructions for Local DNS ---
echo ""
echo "---------------------------------------------------"
echo "ACTION REQUIRED: Configure Local DNS Resolution for *.localcluster"
echo "---------------------------------------------------"
echo "To access services via hostnames like app.localcluster, you need to"
echo "configure your system to resolve *.localcluster domains to the"
echo "Nginx Ingress Controller IP: ${INGRESS_IP}"
echo ""

OS_TYPE="$(uname -s)"

if [[ "$OS_TYPE" == "Darwin" ]]; then
  # macOS Instructions using /etc/resolver
  RESOLVER_FILE="/etc/resolver/localcluster"
  echo "Detected macOS."
  echo "Run the following command to configure DNS resolution for *.localcluster:"
  echo ""
  echo "  echo \"nameserver ${INGRESS_IP}\" | sudo tee ${RESOLVER_FILE}"
  echo ""
  echo "This command creates '${RESOLVER_FILE}' and tells macOS to use"
  echo "${INGRESS_IP} as the DNS server for any *.localcluster domains."
  echo "You will be prompted for your administrator password."
  echo ""
  echo "To verify after running the command: scutil --dns | grep -A 2 localcluster"
  echo "To remove this configuration later: sudo rm ${RESOLVER_FILE}"

elif [[ "$OS_TYPE" == "Linux" ]]; then
  # Linux/Ubuntu Instructions using /etc/hosts
  HOSTS_FILE="/etc/hosts"
  echo "Detected Linux."
  echo "Edit your ${HOSTS_FILE} file using sudo (e.g., 'sudo nano ${HOSTS_FILE}')\""
  echo "and add entries mapping your desired hostnames to the Ingress IP."
  echo ""
  echo "Add lines like this example (replace with your actual app hostnames):"
  echo ""
  echo "  ${INGRESS_IP} grafana.localcluster prometheus.localcluster your-app.localcluster"
  echo ""
else
  # Fallback for other OS types
  HOSTS_FILE="/etc/hosts" # Assuming /etc/hosts is the most likely fallback
  echo "Detected OS: ${OS_TYPE}."
  echo "Attempting configuration via ${HOSTS_FILE}. If this is incorrect for your OS,"
  echo "please manually configure your system to resolve *.localcluster domains"
  echo "to the Ingress IP: ${INGRESS_IP}"
  echo ""
  echo "Edit your ${HOSTS_FILE} file (likely requiring administrator privileges)"
  echo "and add entries mapping your desired hostnames to the Ingress IP."
  echo ""
  echo "Add lines like this example (replace with your actual app hostnames):"
  echo ""
  echo "  ${INGRESS_IP} grafana.localcluster prometheus.localcluster your-app.localcluster"
fi

echo ""
echo "Remember to create Kubernetes Ingress resources for your applications"
echo "using hostnames ending in .localcluster (e.g., host: myapp.localcluster)."
echo "---------------------------------------------------"
# --- END Instructions for Local DNS ---

echo "Bootstrap complete. Press Ctrl+C to stop port-forwarding when finished."
