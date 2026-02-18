#!/bin/bash
# Setup SonarQube server and credentials for Argo Workflows

set -e

SONARQUBE_NAMESPACE="sonarqube"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argo}"

echo "🚀 Setting up SonarQube for Argo Workflows..."
echo ""

# Step 1: Deploy SonarQube
echo "📦 Step 1: Deploying SonarQube server..."
kubectl apply -f sonarqube-deployment.yaml

echo "⏳ Waiting for SonarQube to be ready..."
kubectl wait --for=condition=available --timeout=300s deployment/sonarqube -n ${SONARQUBE_NAMESPACE} || {
  echo "⚠️  SonarQube deployment taking longer than expected"
  echo "   Check status with: kubectl get pods -n ${SONARQUBE_NAMESPACE}"
}

# Step 2: Get SonarQube service URL
SONARQUBE_SERVICE="${SONARQUBE_NAMESPACE}/sonarqube:9000"
echo ""
echo "✅ SonarQube deployed!"
echo "   Service URL: ${SONARQUBE_SERVICE}"
echo ""

# Step 3: Instructions for getting token
echo "📋 Step 2: Get SonarQube Token"
echo ""
echo "To get your SonarQube token:"
echo ""
echo "1. Port-forward to SonarQube:"
echo "   kubectl port-forward -n ${SONARQUBE_NAMESPACE} svc/sonarqube 9000:9000"
echo ""
echo "2. Open browser: http://localhost:9000"
echo ""
echo "3. Login with default credentials:"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "4. Go to: My Account > Security > Generate Token"
echo "   - Name: argo-workflows"
echo "   - Type: User Token"
echo "   - Click Generate"
echo ""
echo "5. Copy the generated token"
echo ""
read -p "Press Enter after you have your SonarQube token..."

# Step 4: Create secret
echo ""
echo "🔐 Step 3: Creating SonarQube credentials secret..."
read -p "Enter your SonarQube token: " SONARQUBE_TOKEN

if [ -z "$SONARQUBE_TOKEN" ]; then
  echo "❌ Token cannot be empty"
  exit 1
fi

# Check if secret already exists
if kubectl get secret sonarqube-credentials -n ${ARGO_NAMESPACE} >/dev/null 2>&1; then
  echo "⚠️  Secret already exists, updating..."
  kubectl delete secret sonarqube-credentials -n ${ARGO_NAMESPACE}
fi

kubectl create secret generic sonarqube-credentials \
  --from-literal=token="${SONARQUBE_TOKEN}" \
  -n ${ARGO_NAMESPACE}

echo ""
echo "✅ SonarQube setup complete!"
echo ""
echo "📝 Configuration Summary:"
echo "   SonarQube URL: http://${SONARQUBE_SERVICE}"
echo "   Secret: sonarqube-credentials (in ${ARGO_NAMESPACE} namespace)"
echo ""
echo "🚀 You can now run the SonarQube workflow:"
echo ""
echo "kubectl create -f - -n ${ARGO_NAMESPACE} << 'EOF'"
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
echo "      value: \"http://${SONARQUBE_SERVICE}\""
echo "    - name: sonar-project-key"
echo "      value: \"my-project\""
echo "    - name: sonar-project-name"
echo "      value: \"My Project\""
echo "EOF"
echo ""
