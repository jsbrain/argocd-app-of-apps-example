#!/bin/bash

# Wait for ingress-nginx to be ready
until kubectl get svc -n ingress-nginx ingress-nginx-controller &>/dev/null; do
  echo "Waiting for ingress-nginx service..."
  sleep 5
done

echo "Starting port forwarding for ingress-nginx..."
kubectl port-forward -n ingress-nginx service/ingress-nginx-controller 8080:80 8443:443 &

echo "Port forwarding started. Services are available at:"
echo "http://[service].localcluster:8080"
echo "https://[service].localcluster:8443"
echo "- https://argocd.localcluster:8443 (ArgoCD UI)"
echo "- https://prometheus.localcluster:8443 (Prometheus)"
echo "- https://grafana.localcluster:8443 (Grafana)"
echo "- https://hello-world.localcluster:8443 (Hello World app)"
echo "- https://guestbook.localcluster:8443 (Guestbook app)"
echo "- https://hello-kubernetes.localcluster:8443 (Hello Kubernetes app)"
