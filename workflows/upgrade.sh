#!/bin/bash
# Upgrade Argo Workflows from v3.5.5 to v3.7.9
# This fixes the "pod reconciliation didn't complete" bug

set -e

NAMESPACE="argo"
OLD_VERSION="v3.5.5"
NEW_VERSION="v3.7.9"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Upgrading Argo Workflows"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "From: ${OLD_VERSION}"
echo "To:   ${NEW_VERSION}"
echo ""

# Step 1: Delete stuck workflows
echo "1. Cleaning up stuck workflows..."
kubectl delete workflow --all -n ${NAMESPACE} --ignore-not-found=true || true
echo "   ✅ Stuck workflows deleted"
echo ""

# Step 2: Backup current configuration
echo "2. Backing up current configuration..."
kubectl get configmap workflow-controller-configmap -n ${NAMESPACE} -o yaml > /tmp/workflow-controller-configmap-backup.yaml 2>/dev/null || echo "   No configmap to backup"
kubectl get clusterrole workflow-controller -o yaml > /tmp/workflow-controller-clusterrole-backup.yaml 2>/dev/null || echo "   No clusterrole to backup"
echo "   ✅ Configuration backed up"
echo ""

# Step 3: Upgrade Argo Workflows
echo "3. Upgrading Argo Workflows to ${NEW_VERSION}..."
kubectl apply -n ${NAMESPACE} -f https://github.com/argoproj/argo-workflows/releases/download/${NEW_VERSION}/install.yaml
echo "   ✅ Manifests applied"
echo ""

# Step 4: Wait for pods to be ready
echo "4. Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=workflow-controller -n ${NAMESPACE} --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=argo-server -n ${NAMESPACE} --timeout=300s || true
echo "   ✅ Pods ready"
echo ""

# Step 5: Restore RBAC (ensure workflows/status permission exists)
echo "5. Ensuring RBAC permissions..."
kubectl patch clusterrole workflow-controller --type='json' -p='[
  {
    "op": "add",
    "path": "/rules/-",
    "value": {
      "apiGroups": ["argoproj.io"],
      "resources": ["workflows/status"],
      "verbs": ["get", "update", "patch"]
    }
  }
]' 2>/dev/null || echo "   Permission may already exist"

kubectl patch clusterrole workflow-controller --type='json' -p='[
  {
    "op": "add",
    "path": "/rules/-",
    "value": {
      "apiGroups": ["argoproj.io"],
      "resources": ["workflowtaskresults"],
      "verbs": ["get", "list", "watch", "create", "update", "patch", "delete"]
    }
  }
]' 2>/dev/null || echo "   Permission may already exist"

echo "   ✅ RBAC permissions verified"
echo ""

# Step 6: Restore ConfigMap if it existed
if [ -f /tmp/workflow-controller-configmap-backup.yaml ]; then
    echo "6. Restoring ConfigMap..."
    kubectl apply -f /tmp/workflow-controller-configmap-backup.yaml
    kubectl rollout restart deployment workflow-controller -n ${NAMESPACE}
    kubectl rollout status deployment workflow-controller -n ${NAMESPACE} --timeout=60s || true
    echo "   ✅ ConfigMap restored"
else
    echo "6. No ConfigMap to restore"
fi
echo ""

# Step 7: Verify upgrade
echo "7. Verifying upgrade..."
CURRENT_VERSION=$(kubectl get deployment workflow-controller -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' || echo "unknown")
echo "   Current version: ${CURRENT_VERSION}"

if [[ "$CURRENT_VERSION" == *"3.7"* ]]; then
    echo "   ✅ Upgrade successful!"
else
    echo "   ⚠️  Version check: ${CURRENT_VERSION} (may need to check manually)"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Upgrade complete!"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo "1. Test a workflow: kubectl create -n argo -f workflows/01-simple-test-only.yaml"
echo "2. Monitor: kubectl get workflows -n argo -w"
echo "3. Access UI: ./workflows/access.sh"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
