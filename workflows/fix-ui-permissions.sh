#!/bin/bash
# Fix UI permissions to view workflow tree

set -e

NAMESPACE="argo"
SA_NAME="argo-ui"

echo "🔧 Fixing UI permissions for workflow tree visualization..."

# Create ClusterRole for pods and events
echo "📋 Creating ClusterRole for pods and events..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argo-ui-pods
rules:
- apiGroups: [""]
  resources: ["pods", "events"]
  verbs: ["list", "get", "watch"]
- apiGroups: [""]
  resources: ["pods/log"]
  verbs: ["get", "list"]
EOF

# Create ClusterRoleBinding
echo "📋 Creating ClusterRoleBinding..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argo-ui-pods
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: argo-ui-pods
subjects:
- kind: ServiceAccount
  name: ${SA_NAME}
  namespace: ${NAMESPACE}
EOF

# Verify
echo ""
echo "✅ Verification:"
kubectl get clusterrole argo-ui-pods
kubectl get clusterrolebinding argo-ui-pods

echo ""
echo "🔍 Checking binding details..."
kubectl get clusterrolebinding argo-ui-pods -o yaml | grep -A 5 "subjects:"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Permissions updated!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Next steps:"
echo "   1. Refresh your browser (hard refresh: Ctrl+Shift+R or Cmd+Shift+R)"
echo "   2. Navigate to your workflow"
echo "   3. The workflow tree should now be visible"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
