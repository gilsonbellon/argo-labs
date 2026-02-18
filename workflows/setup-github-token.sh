#!/bin/bash
# Setup GitHub token secret for Argo Events poller

set -e

NAMESPACE="${NAMESPACE:-argo-events}"
SECRET_NAME="github-token-secret"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <github-token>"
  echo ""
  echo "To get your GitHub token:"
  echo "  1. Go to: https://github.com/settings/tokens"
  echo "  2. Click 'Generate new token' > 'Generate new token (classic)'"
  echo "  3. Give it a name: argo-events-poller"
  echo "  4. Select scopes:"
  echo "     - repo (for private repos)"
  echo "     - public_repo (for public repos)"
  echo "  5. Click 'Generate token'"
  echo "  6. Copy the token immediately"
  echo ""
  echo "Or set environment variable:"
  echo "  export GITHUB_TOKEN=your-token"
  echo "  $0"
  exit 1
fi

GITHUB_TOKEN="${1:-${GITHUB_TOKEN}}"

if [ -z "$GITHUB_TOKEN" ]; then
  echo "❌ Error: GitHub token is required"
  exit 1
fi

echo "🔐 Creating GitHub token secret..."
echo "  Namespace: ${NAMESPACE}"
echo "  Secret name: ${SECRET_NAME}"
echo ""

# Check if secret already exists
if kubectl get secret "${SECRET_NAME}" -n "${NAMESPACE}" >/dev/null 2>&1; then
  echo "⚠️  Secret ${SECRET_NAME} already exists in namespace ${NAMESPACE}"
  read -p "Do you want to update it? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    exit 0
  fi
  kubectl delete secret "${SECRET_NAME}" -n "${NAMESPACE}"
fi

# Create the secret
kubectl create secret generic "${SECRET_NAME}" \
  --from-literal=token="${GITHUB_TOKEN}" \
  -n "${NAMESPACE}"

echo ""
echo "✅ GitHub token secret created successfully!"
echo ""
echo "You can now apply the poller cronjob:"
echo "  kubectl apply -f poller-cronjob.yaml"
echo ""
echo "To verify the secret:"
echo "  kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}"
echo ""
