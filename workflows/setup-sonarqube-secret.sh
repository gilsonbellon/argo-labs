#!/bin/bash
# Setup SonarQube credentials secret for Argo Workflows
# Usage: ./setup-sonarqube-secret.sh <sonarqube-token>

set -e

NAMESPACE="${NAMESPACE:-argo}"
SECRET_NAME="sonarqube-credentials"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <sonarqube-token>"
  echo ""
  echo "Example:"
  echo "  $0 sqp_1234567890abcdef1234567890abcdef12345678"
  echo ""
  echo "To get your SonarQube token:"
  echo "  1. Login to SonarQube"
  echo "  2. Go to: My Account > Security > Generate Token"
  echo "  3. Copy the generated token"
  echo ""
  echo "Or set environment variable:"
  echo "  export SONARQUBE_TOKEN=your-token"
  echo "  $0"
  exit 1
fi

SONARQUBE_TOKEN="${1:-${SONARQUBE_TOKEN}}"

if [ -z "$SONARQUBE_TOKEN" ]; then
  echo "❌ Error: SonarQube token is required"
  exit 1
fi

echo "🔐 Creating SonarQube credentials secret..."
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
  --from-literal=token="${SONARQUBE_TOKEN}" \
  -n "${NAMESPACE}"

echo ""
echo "✅ SonarQube credentials secret created successfully!"
echo ""
echo "You can now run the workflow:"
echo "  kubectl create -f - -n argo << 'EOF'"
echo "apiVersion: argoproj.io/v1alpha1"
echo "kind: Workflow"
echo "metadata:"
echo "  generateName: sonarqube-analysis-test-"
echo "spec:"
echo "  workflowTemplateRef:"
echo "    name: sonarqube-analysis"
echo "  serviceAccountName: argo-workflow"
echo "  arguments:"
echo "    parameters:"
echo "    - name: sonar-host-url"
echo "      value: \"http://your-sonarqube-server:9000\""
echo "    - name: sonar-project-key"
echo "      value: \"your-project-key\""
echo "    - name: sonar-project-name"
echo "      value: \"Your Project Name\""
echo "EOF"
echo ""
echo "To verify the secret:"
echo "  kubectl get secret ${SECRET_NAME} -n ${NAMESPACE}"
echo ""
