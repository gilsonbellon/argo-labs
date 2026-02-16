#!/bin/bash
# Quick fix script to disable ApplicationSet controller in ArgoCD

set -e

echo "Checking ArgoCD namespace..."
kubectl get namespace argocd || {
    echo "Error: argocd namespace not found. Is ArgoCD installed?"
    exit 1
}

echo ""
echo "Checking for ApplicationSet controller..."
if kubectl get deployment argocd-applicationset-controller -n argocd &>/dev/null; then
    echo "Found ApplicationSet controller. Scaling it down..."
    kubectl scale deployment argocd-applicationset-controller -n argocd --replicas=0
    echo "✓ ApplicationSet controller scaled down to 0 replicas"
else
    echo "ApplicationSet controller not found (may already be disabled)"
fi

echo ""
echo "Checking ApplicationSet CRD..."
if kubectl get crd applicationsets.argoproj.io &>/dev/null; then
    echo "ApplicationSet CRD exists. If you want to remove it, run:"
    echo "  kubectl delete crd applicationsets.argoproj.io"
    echo ""
    echo "Note: Removing the CRD will delete any existing ApplicationSet resources."
else
    echo "ApplicationSet CRD not found (this is OK)"
fi

echo ""
echo "Verifying ArgoCD controller status..."
echo "Check logs with: kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50"
echo ""
echo "Done! The ApplicationSet errors should stop appearing in the controller logs."
