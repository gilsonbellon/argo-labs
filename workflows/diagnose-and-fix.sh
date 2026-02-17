#!/bin/bash
# Comprehensive diagnostic and fix script for Argo Workflows stuck workflows

set -e

NAMESPACE="argo"
WF_NAME="${1:-simple-test-wzgtv}"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Argo Workflows Diagnostic & Fix Script"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Check Argo Workflows version
echo "1. Checking Argo Workflows version..."
VERSION=$(kubectl get deployment workflow-controller -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].image}' | grep -oP 'v\d+\.\d+\.\d+' || echo "unknown")
echo "   Version: $VERSION"
if [[ "$VERSION" == "v3.5.5" ]] || [[ "$VERSION" == "v3.5.3" ]] || [[ "$VERSION" == "v3.5.4" ]]; then
    echo "   ⚠️  WARNING: Known buggy version with reconciliation issues!"
fi
echo ""

# Step 2: Check workflow-controller RBAC
echo "2. Checking workflow-controller RBAC..."
SA_NAME=$(kubectl get deployment workflow-controller -n $NAMESPACE -o jsonpath='{.spec.template.spec.serviceAccountName}')
if [ -z "$SA_NAME" ]; then
    SA_NAME="default"
fi
echo "   Service Account: $SA_NAME"

# Check if ClusterRole exists
if kubectl get clusterrole workflow-controller &>/dev/null; then
    echo "   ✅ ClusterRole exists"
    
    # Check for workflowtaskresults permission
    if kubectl get clusterrole workflow-controller -o yaml | grep -q "workflowtaskresults"; then
        echo "   ✅ Has workflowtaskresults permission"
    else
        echo "   ⚠️  Missing workflowtaskresults permission - adding..."
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
        ]'
    fi
    
    # Check for workflows/status permission (critical for status updates)
    if kubectl get clusterrole workflow-controller -o yaml | grep -q "workflows/status"; then
        echo "   ✅ Has workflows/status permission"
    else
        echo "   ⚠️  Missing workflows/status permission - adding..."
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
        ]'
    fi
else
    echo "   ❌ ClusterRole missing!"
fi

# Check binding
if kubectl get clusterrolebinding workflow-controller &>/dev/null; then
    echo "   ✅ ClusterRoleBinding exists"
else
    echo "   ❌ ClusterRoleBinding missing!"
fi
echo ""

# Step 3: Check for incomplete WorkflowTaskResults
echo "3. Checking for incomplete WorkflowTaskResults..."
WTR_COUNT=$(kubectl get workflowtaskresults -n $NAMESPACE --no-headers 2>/dev/null | wc -l || echo "0")
if [ "$WTR_COUNT" -gt 0 ]; then
    echo "   Found $WTR_COUNT WorkflowTaskResult(s)"
    INCOMPLETE=$(kubectl get workflowtaskresults -n $NAMESPACE -o jsonpath='{.items[?(@.metadata.labels.workflows\.argoproj\.io/report-outputs-completed=="false")].metadata.name}' 2>/dev/null || echo "")
    if [ -n "$INCOMPLETE" ]; then
        echo "   ⚠️  Found incomplete WorkflowTaskResults: $INCOMPLETE"
        echo "   Fixing by deleting incomplete ones..."
        kubectl delete workflowtaskresults -n $NAMESPACE -l workflows.argoproj.io/report-outputs-completed=false 2>/dev/null || true
    else
        echo "   ✅ All WorkflowTaskResults are complete"
    fi
else
    echo "   ✅ No WorkflowTaskResults found"
fi
echo ""

# Step 4: Check stuck workflow
if [ -n "$WF_NAME" ] && kubectl get workflow $WF_NAME -n $NAMESPACE &>/dev/null; then
    echo "4. Analyzing stuck workflow: $WF_NAME"
    
    PHASE=$(kubectl get workflow $WF_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
    echo "   Phase: $PHASE"
    
    # Check node statuses
    echo "   Node statuses:"
    kubectl get workflow $WF_NAME -n $NAMESPACE -o jsonpath='{.status.nodes}' | jq -r 'to_entries[] | "      \(.key): \(.value.phase // "Unknown")"' 2>/dev/null || echo "      (Unable to parse)"
    
    # Check ResourceVersion
    RV=$(kubectl get workflow $WF_NAME -n $NAMESPACE -o jsonpath='{.metadata.resourceVersion}')
    echo "   ResourceVersion: $RV"
    
    # Check if stuck in reconciliation
    RECONCILE_COUNT=$(kubectl logs -n $NAMESPACE -l app=workflow-controller --tail=100 | grep -c "pod reconciliation didn't complete" || echo "0")
    if [ "$RECONCILE_COUNT" -gt 5 ]; then
        echo "   ⚠️  Workflow appears stuck in reconciliation loop"
        echo ""
        echo "   Attempting to fix..."
        
        # Try to force update by patching status
        echo "   Option 1: Trying to patch workflow status..."
        kubectl patch workflow $WF_NAME -n $NAMESPACE --type='json' -p='[{"op": "replace", "path": "/metadata/resourceVersion", "value": ""}]' 2>/dev/null || echo "      Patch failed (this is expected)"
        
        # Restart workflow-controller
        echo "   Option 2: Restarting workflow-controller..."
        kubectl rollout restart deployment workflow-controller -n $NAMESPACE
        kubectl rollout status deployment workflow-controller -n $NAMESPACE --timeout=60s
        
        echo "   Waiting 30 seconds for reconciliation..."
        sleep 30
        
        # Check if it progressed
        NEW_PHASE=$(kubectl get workflow $WF_NAME -n $NAMESPACE -o jsonpath='{.status.phase}')
        if [ "$NEW_PHASE" != "$PHASE" ]; then
            echo "   ✅ Workflow progressed! New phase: $NEW_PHASE"
        else
            echo "   ⚠️  Still stuck. This may be a v3.5.5 bug."
            echo "   Recommendation: Upgrade Argo Workflows or delete/recreate workflow"
        fi
    fi
else
    echo "4. No workflow specified or workflow not found"
fi
echo ""

# Step 5: Check workflow-controller logs for errors
echo "5. Recent workflow-controller errors:"
kubectl logs -n $NAMESPACE -l app=workflow-controller --tail=20 | grep -i "error\|failed\|denied" | tail -5 || echo "   No recent errors found"
echo ""

# Step 6: Recommendations
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Recommendations:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$VERSION" == "v3.5.5" ]]; then
    echo "1. ⚠️  Upgrade Argo Workflows to v3.5.7+ or v3.6+"
    echo "   Known bugs in v3.5.5 cause reconciliation issues"
fi
echo "2. Ensure workflow-controller has workflows/status permission"
echo "3. Delete stuck workflows and recreate them"
echo "4. Check for incomplete WorkflowTaskResults regularly"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
