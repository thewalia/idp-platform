#!/bin/bash

echo "removing finalizer..."
kubectl patch application <name> -n argocd --type json -p='[{"op": "remove", "path": "/metadata/finalizers"}]'

echo "reapplying idp-root-app..."
kubectl apply -f bootstrap/root-app.yaml

echo "monitoring progress..."
kubectl get pods -A | grep -E "(demo-apps|vault|external-secrets|argocd)"
