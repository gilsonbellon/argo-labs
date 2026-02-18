#!/bin/bash
# Guide to get SonarQube token

set -e

SONARQUBE_NAMESPACE="sonarqube"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argo}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔐 Getting SonarQube Token"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if SonarQube is running
if ! kubectl get deployment sonarqube -n ${SONARQUBE_NAMESPACE} >/dev/null 2>&1; then
  echo "❌ SonarQube is not deployed yet!"
  echo ""
  echo "Deploy it first:"
  echo "  kubectl apply -f sonarqube-deployment.yaml"
  echo ""
  exit 1
fi

# Check if pod is ready
POD_STATUS=$(kubectl get pods -n ${SONARQUBE_NAMESPACE} -l app=sonarqube -o jsonpath='{.items[0].status.phase}' 2>/dev/null || echo "NotFound")

if [ "$POD_STATUS" != "Running" ]; then
  echo "⏳ SonarQube is starting up..."
  echo "   Current status: ${POD_STATUS}"
  echo ""
  echo "Waiting for SonarQube to be ready (this may take 2-3 minutes)..."
  kubectl wait --for=condition=ready pod -l app=sonarqube -n ${SONARQUBE_NAMESPACE} --timeout=300s || {
    echo ""
    echo "⚠️  SonarQube is taking longer than expected"
    echo "   Check status: kubectl get pods -n ${SONARQUBE_NAMESPACE}"
    echo ""
    exit 1
  }
fi

echo "✅ SonarQube is ready!"
echo ""

# Step 1: Port-forward instructions
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 1: Access SonarQube UI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "In a NEW terminal, run this command to port-forward:"
echo ""
echo "  kubectl port-forward -n ${SONARQUBE_NAMESPACE} svc/sonarqube 9000:9000"
echo ""
echo "Keep that terminal open, then:"
echo ""
read -p "Press Enter after you've started the port-forward..."

# Step 2: Access UI
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 2: Login to SonarQube"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Open your browser and go to: http://localhost:9000"
echo ""
echo "2. Login with default credentials:"
echo "   Username: admin"
echo "   Password: admin"
echo ""
echo "3. You'll be prompted to change the password - do that now"
echo ""
read -p "Press Enter after you've logged in and changed the password..."

# Step 3: Generate token
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Generate Token"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "1. Click on your user icon (top right) > My Account"
echo ""
echo "2. Go to the 'Security' tab"
echo ""
echo "3. Under 'Generate Tokens', enter:"
echo "   Name: argo-workflows"
echo "   Type: User Token"
echo "   Expires in: (leave default or set as needed)"
echo ""
echo "4. Click 'Generate'"
echo ""
echo "5. COPY THE TOKEN IMMEDIATELY (you won't see it again!)"
echo ""
read -p "Press Enter after you've copied your token..."

# Step 4: Create secret
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Create Kubernetes Secret"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
read -p "Paste your SonarQube token here: " SONARQUBE_TOKEN

if [ -z "$SONARQUBE_TOKEN" ]; then
  echo "❌ Token cannot be empty"
  exit 1
fi

# Validate token format (SonarQube tokens are usually alphanumeric, 40+ chars)
if [ ${#SONARQUBE_TOKEN} -lt 20 ]; then
  echo "⚠️  Warning: Token seems too short. SonarQube tokens are usually 40+ characters."
  read -p "Continue anyway? (y/N): " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    exit 1
  fi
fi

# Check if secret already exists
if kubectl get secret sonarqube-credentials -n ${ARGO_NAMESPACE} >/dev/null 2>&1; then
  echo ""
  echo "⚠️  Secret already exists. Updating..."
  kubectl delete secret sonarqube-credentials -n ${ARGO_NAMESPACE}
fi

kubectl create secret generic sonarqube-credentials \
  --from-literal=token="${SONARQUBE_TOKEN}" \
  -n ${ARGO_NAMESPACE}

echo ""
echo "✅ SonarQube token secret created successfully!"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Setup Complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Your SonarQube configuration:"
echo "  Server URL: http://sonarqube.sonarqube.svc:9000"
echo "  Secret: sonarqube-credentials (in ${ARGO_NAMESPACE} namespace)"
echo ""
echo "You can now run the SonarQube workflow!"
echo ""
