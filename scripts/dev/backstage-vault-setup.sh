#!/bin/bash

# Backstage Vault Setup Script
# This script sets up Vault secrets for Backstage integration

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Vault configuration
VAULT_ADDR="http://localhost:8200"
VAULT_TOKEN_FILE="$HOME/.vault-token"

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if Vault is accessible
check_vault_status() {
    print_status "Checking Vault connectivity..."
    
    if ! command -v vault &> /dev/null; then
        print_error "Vault CLI not found. Please install Vault CLI."
        exit 1
    fi
    
    # Port forward Vault if not already accessible
    if ! curl -s "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
        print_warning "Vault not accessible at $VAULT_ADDR"
        print_status "Starting kubectl port-forward for Vault..."
        kubectl port-forward -n vault svc/vault 8200:8200 > /dev/null 2>&1 &
        PORT_FORWARD_PID=$!
        sleep 5
        
        if ! curl -s "$VAULT_ADDR/v1/sys/health" > /dev/null 2>&1; then
            print_error "Unable to connect to Vault after port-forward"
            kill $PORT_FORWARD_PID 2>/dev/null || true
            exit 1
        fi
    fi
    
    export VAULT_ADDR="$VAULT_ADDR"
    
    # Check if we have a valid token
    if [[ ! -f "$VAULT_TOKEN_FILE" ]]; then
        print_error "Vault token not found at $VAULT_TOKEN_FILE"
        print_error "Please run the main vault-setup.sh script first"
        exit 1
    fi
    
    export VAULT_TOKEN=$(cat "$VAULT_TOKEN_FILE")
    
    if ! vault token lookup > /dev/null 2>&1; then
	    print_error "Invalid or expired Vault token. Please re-run vault-setup.sh"
	    exit 1
    fi


    
    print_status "Vault connectivity verified"
}

# Function to create Backstage secrets
create_backstage_secrets() {
    print_status "Creating Backstage secrets in Vault..."
    
    # GitHub integration secrets
    print_status "Setting up GitHub integration secrets..."
    read -p "Enter GitHub Personal Access Token: " -s GITHUB_TOKEN
    echo
    read -p "Enter GitHub OAuth App Client ID (optional, press enter to skip): " GITHUB_CLIENT_ID
    read -p "Enter GitHub OAuth App Client Secret (optional, press enter to skip): " -s GITHUB_CLIENT_SECRET
    echo
    
    # Create GitHub secrets
    vault kv put secret/backstage/github \
        token="$GITHUB_TOKEN" \
        client-id="${GITHUB_CLIENT_ID:-dummy-client-id}" \
        client-secret="${GITHUB_CLIENT_SECRET:-dummy-client-secret}"
    
    print_status "GitHub secrets created successfully"
    
    # Database secrets
    print_status "Setting up database secrets..."
    DB_PASSWORD=$(openssl rand -base64 32)
    vault kv put secret/backstage/database \
        postgres-password="$DB_PASSWORD"
    
    print_status "Database secrets created successfully"
    
    # ArgoCD integration secrets
    print_status "Setting up ArgoCD integration secrets..."
    
    # Get ArgoCD admin password
    ARGOCD_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
    
    # Create a token (this would normally be done through ArgoCD API)
    vault kv put secret/backstage/argocd \
        password="$ARGOCD_PASSWORD" \
        token="dummy-token-replace-with-real-token"
    
    print_status "ArgoCD secrets created successfully"
    print_warning "Note: ArgoCD token is set to dummy value. Update it with a real token from ArgoCD UI."
}

# Function to verify secrets
verify_secrets() {
    print_status "Verifying created secrets..."
    
    # Check GitHub secrets
    if vault kv get secret/backstage/github > /dev/null 2>&1; then
        print_status "✓ GitHub secrets verified"
    else
        print_error "✗ GitHub secrets not found"
        return 1
    fi
    
    # Check database secrets
    if vault kv get secret/backstage/database > /dev/null 2>&1; then
        print_status "✓ Database secrets verified"
    else
        print_error "✗ Database secrets not found"
        return 1
    fi
    
    # Check ArgoCD secrets
    if vault kv get secret/backstage/argocd > /dev/null 2>&1; then
        print_status "✓ ArgoCD secrets verified"
    else
        print_error "✗ ArgoCD secrets not found"
        return 1
    fi
    
    print_status "All secrets verified successfully"
}

# Function to create Kubernetes auth role for Backstage
create_kubernetes_auth_role() {
    print_status "Creating Kubernetes auth role for Backstage..."
    
    # Create policy for Backstage secrets
    vault policy write backstage-secrets - <<EOF
path "secret/data/backstage/*" {
  capabilities = ["read"]
}
path "secret/metadata/backstage/*" {
  capabilities = ["list", "read"]
}
EOF
    
    # Create Kubernetes auth role
    vault write auth/kubernetes/role/backstage \
        bound_service_account_names=backstage \
        bound_service_account_namespaces=backstage \
        policies=backstage-secrets \
        ttl=24h
    
    print_status "Kubernetes auth role created successfully"
}

# Function to display next steps
display_next_steps() {
    echo
    print_status "Backstage Vault setup completed successfully!"
    echo
    print_status "Next steps:"
    echo "1. Deploy Backstage using ArgoCD:"
    echo "   kubectl apply -f bootstrap/argocd-apps/backstage-app.yaml"
    echo
    echo "2. Access Backstage (after deployment):"
    echo "   kubectl port-forward -n backstage svc/backstage 7007:7007"
    echo "   Open http://localhost:7007"
    echo
    echo "3. Update ArgoCD token in Vault:"
    echo "   - Generate token in ArgoCD UI: Settings > Accounts > admin > Generate Token"
    echo "   - Update Vault: vault kv patch secret/backstage/argocd token=<real-token>"
    echo
    print_warning "Important: The GitHub token should have the following permissions:"
    echo "- repo (for private repos)"
    echo "- read:org (for organization access)"
    echo "- read:user (for user information)"
    echo "- user:email (for user email)"
}

# Main execution
main() {
    echo "================================================"
    echo "Backstage Vault Setup Script"
    echo "================================================"
    echo
    
    check_vault_status
    create_backstage_secrets
    verify_secrets
    create_kubernetes_auth_role
    display_next_steps
    
    # Clean up port-forward if we started it
    if [[ -n "${PORT_FORWARD_PID:-}" ]]; then
        kill $PORT_FORWARD_PID 2>/dev/null || true
    fi
}

# Run main function
main "$@"
