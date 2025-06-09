#!/bin/bash
set -e

echo "🔧 Setting up Vault for ESO integration..."

# Create vault-auth ServiceAccount first (dependency)
echo "👤 Creating vault-auth ServiceAccount..."
kubectl apply -f - <<EOF
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vault-auth
  namespace: vault
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vault-auth-delegator
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: system:auth-delegator
subjects:
- kind: ServiceAccount
  name: vault-auth
  namespace: vault
EOF

# Wait for ServiceAccount to be ready
sleep 5
# Port forward to Vault (run in background)
echo "🔗 Setting up port forward to Vault..."
kubectl port-forward -n vault svc/vault 8200:8200 &
PF_PID=$!
sleep 5

# Set Vault address
export VAULT_ADDR='http://127.0.0.1:8200'

# Check if Vault is unsealed (assuming it's already initialized)
echo "📊 Checking Vault status..."
vault status

# Enable KV v2 secrets engine if not already enabled
echo "🔑 Enabling KV v2 secrets engine..."
vault secrets enable -path=secret kv-v2 || echo "KV v2 already enabled"

# Enable Kubernetes auth method
echo "🔐 Enabling Kubernetes auth method..."
vault auth enable kubernetes || echo "Kubernetes auth already enabled"

# Get Kubernetes cluster info
K8S_HOST="https://kubernetes.default.svc:443"
K8S_CACERT=$(kubectl config view --raw --minify --flatten -o jsonpath='{.clusters[].cluster.certificate-authority-data}' | base64 --decode)

# Create token for vault-auth ServiceAccount
echo "🔑 Creating token for vault-auth ServiceAccount..."
VAULT_SA_TOKEN=$(kubectl create token vault-auth -n vault --duration=8760h)

# Configure Kubernetes auth
echo "⚙️ Configuring Kubernetes auth..."
vault write auth/kubernetes/config \
    token_reviewer_jwt="$VAULT_SA_TOKEN" \
    kubernetes_host="$K8S_HOST" \
    kubernetes_ca_cert="$K8S_CACERT"

# Create policy for demo-nginx app
echo "📝 Creating policy for demo-nginx..."
vault policy write demo-nginx-policy - <<EOF
path "secret/data/demo-nginx/*" {
  capabilities = ["read"]
}
EOF

# Create role for demo-nginx
echo "👤 Creating role for demo-nginx..."
vault write auth/kubernetes/role/demo-nginx \
    bound_service_account_names=demo-nginx \
    bound_service_account_namespaces=demo-apps \
    policies=demo-nginx-policy \
    ttl=24h

# Create sample secrets
echo "🔒 Creating sample secrets..."
vault kv put secret/demo-nginx/config \
    api_key="demo-api-key-12345" \
    database_url="postgresql://user:pass@db.example.com:5432/mydb" \
    debug_mode="true"

vault kv put secret/demo-nginx/creds \
    username="nginx-user" \
    password="super-secret-password"

echo "✅ Vault setup complete!"
echo "🔑 Created secrets at:"
echo "  - secret/demo-nginx/config"
echo "  - secret/demo-nginx/creds"

# Kill port-forward
kill $PF_PID || true
