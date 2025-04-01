#!/bin/bash

# Wait for ingress-nginx to be ready
until kubectl get svc -n ingress-nginx ingress-nginx-controller &>/dev/null; do
  echo "Waiting for ingress-nginx service..."
  sleep 5
done

# Get ArgoCD admin password
echo ""
echo "ArgoCD login information:"
echo "------------------------"
echo "Username: admin"
echo "Password: $(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)"
echo "------------------------"
echo ""

echo "Port forwarding starting. Services will be available at:"
echo "http://[service].localcluster:8880"
echo "https://[service].localcluster:8443"
echo "- https://argocd.localcluster:8443 (ArgoCD UI)"
echo "- https://prometheus.localcluster:8443 (Prometheus)"
echo "- https://grafana.localcluster:8443 (Grafana)"
echo "- https://hello-world.localcluster:8443 (Hello World app)"
echo "- https://guestbook.localcluster:8443 (Guestbook app)"
echo "- https://hello-kubernetes.localcluster:8443 (Hello Kubernetes app)"

echo "Starting port forwarding for ingress-nginx..."
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8880:80 8443:443
