#!/bin/bash
# Setup Harbor credentials secret for Argo Workflows
# Usage: ./setup-harbor-secret.sh <username> <password>

set -e

NAMESPACE="${NAMESPACE:-argo}"
SECRET_NAME="harbor-credentials"

if [ $# -lt 2 ]; then
  echo "Usage: $0 <harbor-username> <harbor-password>"
  echo ""
  echo "Example:"
  echo "  $0 admin Harbor12345"
  echo ""
  echo "Or set environment variables:"
  echo "  export HARBOR_USERNAME=admin"
  echo "  export HARBOR_PASSWORD=Harbor12345"
  echo "  $0"
  exit 1
fi

HARBOR_USERNAME="${1:-${HARBOR_USERNAME}}"
HARBOR_PASSWORD="${2:-${HARBOR_PASSWORD}}"

if [ -z "$HARBOR_USERNAME" ] || [ -z "$HARBOR_PASSWORD" ]; then
  echo "❌ Error: Harbor username and password are required"
  exit 1
fi

echo "🔐 Creating Harbor credentials secret..."
echo "  Namespace: ${NAMESPACE}"
echo "  Secret name: ${SECRET_NAME}"
echo "  Username: ${HARBOR_USERNAME}"
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
  --from-literal=username="${HARBOR_USERNAME}" \
  --from-literal=password="${HARBOR_PASSWORD}" \
  -n "${NAMESPACE}"

echo ""
echo "✅ Harbor credentials secret created successfully!"
echo ""
echo "You can now run the workflow:"
echo "  argo submit --from workflowtemplate/harbor-build-push -p repository=my-app"
echo ""
echo "To verify the secret:"
echo "  kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}"
echo ""
