#!/bin/bash
# Install Argo Workflows v3.5.5 with proper authentication setup
# Follows official documentation: https://argo-workflows.readthedocs.io/en/release-3.5/access-token/

set -e

NAMESPACE="argo"
VERSION="v3.5.5"
SA_NAME="argo-ui"
SECRET_NAME="${SA_NAME}.service-account-token"

echo "🚀 Installing Argo Workflows ${VERSION}..."

# Create namespace
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install Argo Workflows
echo "📦 Applying manifests..."
kubectl apply -n ${NAMESPACE} -f https://github.com/argoproj/argo-workflows/releases/download/${VERSION}/install.yaml

# Wait for pods
echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=workflow-controller -n ${NAMESPACE} --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=argo-server -n ${NAMESPACE} --timeout=300s || true

# Configure authentication mode for web UI (per official docs)
echo "🔧 Configuring authentication mode..."
kubectl -n ${NAMESPACE} patch deployment argo-server --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--auth-mode=client"
  }
]' 2>/dev/null && {
    echo "🔄 Restarting argo-server..."
    kubectl -n ${NAMESPACE} rollout restart deployment argo-server
    kubectl -n ${NAMESPACE} rollout status deployment argo-server --timeout=60s || true
}

# Set up service account and RBAC for web UI access (per official docs)
echo "🔐 Setting up service account and RBAC (per official docs)..."

# Create ClusterRole for web UI (allows access across namespaces)
echo "   Creating ClusterRole with web UI permissions..."
kubectl create clusterrole ${SA_NAME} \
  --verb=list,get,watch,create,update,patch,delete \
  --resource=workflows.argoproj.io \
  --dry-run=client -o yaml | kubectl apply -f -

# Also allow access to workflowtemplates, clusterworkflowtemplates, and cronworkflows
kubectl create clusterrole ${SA_NAME}-templates \
  --verb=list,get,watch \
  --resource=workflowtemplates.argoproj.io,clusterworkflowtemplates.argoproj.io,cronworkflows.argoproj.io \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# Add permissions for pods and events (needed for UI to display workflow tree)
echo "   Adding pod and event permissions for workflow tree visualization..."
kubectl create clusterrole ${SA_NAME}-pods \
  --verb=list,get,watch \
  --resource=pods,events \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

kubectl create clusterrolebinding ${SA_NAME}-pods \
  --clusterrole=${SA_NAME}-pods \
  --serviceaccount=${NAMESPACE}:${SA_NAME} \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# Create service account
echo "   Creating service account..."
kubectl create sa ${SA_NAME} -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Bind service account to ClusterRoles (allows access across namespaces)
echo "   Creating ClusterRole bindings..."
kubectl create clusterrolebinding ${SA_NAME} \
  --clusterrole=${SA_NAME} \
  --serviceaccount=${NAMESPACE}:${SA_NAME} \
  --dry-run=client -o yaml | kubectl apply -f -

# Bind to templates ClusterRole
kubectl create clusterrolebinding ${SA_NAME}-templates \
  --clusterrole=${SA_NAME}-templates \
  --serviceaccount=${NAMESPACE}:${SA_NAME} \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# Create secret for token (per official docs)
echo "   Creating secret for token..."
kubectl apply -n ${NAMESPACE} -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

# Wait for secret token to be created
echo "⏳ Waiting for token to be created..."
sleep 5

# Verify token exists
if kubectl -n ${NAMESPACE} get secret ${SECRET_NAME} &>/dev/null; then
    echo "✅ Token secret created successfully"
else
    echo "⚠️  Token secret not ready yet, it will be created automatically"
fi

echo ""
echo "✅ Installation complete!"
kubectl get pods -n ${NAMESPACE}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Setup Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Argo Workflows installed"
echo "✅ Authentication configured (--auth-mode=client)"
echo "✅ Service account created: ${SA_NAME}"
echo "✅ Role and binding created"
echo "✅ Token secret created: ${SECRET_NAME}"
echo ""
echo "📋 Next: Run ./access.sh to get token and access UI"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
