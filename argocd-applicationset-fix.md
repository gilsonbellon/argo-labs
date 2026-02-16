# Fixing ArgoCD ApplicationSet CRD Error

## Problem

The ArgoCD controller is showing errors:
```
"error":"failed to get restmapping: no matches for kind \"ApplicationSet\" in version \"argoproj.io/v1alpha1\""
```

This happens because the ApplicationSet controller is enabled but the ApplicationSet CRD is not installed.

## Solution Options

### Option 1: Install ApplicationSet CRD (If you want to use ApplicationSet)

ApplicationSet allows you to manage multiple ArgoCD Applications declaratively. If you want this functionality:

**For Argo CD v2.3+:**
ApplicationSet is bundled with Argo CD, but you may need to ensure it's enabled:

```bash
# Check if ApplicationSet is already installed
kubectl get crd applicationsets.argoproj.io

# If not installed, install it (version depends on your ArgoCD version)
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/applicationset/v0.4.0/manifests/install.yaml
```

**For Argo CD v2.3+:**
The ApplicationSet controller should be included. Check your ArgoCD installation:

```bash
# Check ArgoCD version
kubectl get deployment argocd-applicationset-controller -n argocd

# If it doesn't exist, check your ArgoCD installation method
```

### Option 2: Disable ApplicationSet Controller (Recommended if you don't need it)

If you don't need ApplicationSet functionality, disable the controller:

#### Method A: Disable via Helm (if installed via Helm)

```bash
# Check if installed via Helm
helm list -n argocd

# If yes, upgrade with ApplicationSet disabled
helm upgrade argocd argo/argo-cd \
  --namespace argocd \
  --set applicationSet.enabled=false
```

#### Method B: Disable via Kustomize/Manifests

If you installed ArgoCD via manifests, you need to remove or disable the ApplicationSet controller:

1. **Find the ApplicationSet controller deployment:**
   ```bash
   kubectl get deployment -n argocd | grep applicationset
   ```

2. **Scale down or delete the controller:**
   ```bash
   # Option 1: Scale down to 0
   kubectl scale deployment argocd-applicationset-controller -n argocd --replicas=0
   
   # Option 2: Delete the deployment (if you're sure you don't need it)
   kubectl delete deployment argocd-applicationset-controller -n argocd
   ```

3. **Update ArgoCD controller to disable ApplicationSet watching:**

   Edit the ArgoCD Application Controller deployment:
   ```bash
   kubectl edit deployment argocd-application-controller -n argocd
   ```

   Look for environment variables and ensure ApplicationSet watching is disabled, or remove any ApplicationSet-related configuration.

#### Method C: Patch the Deployment (Quick Fix)

```bash
# Scale down ApplicationSet controller
kubectl scale deployment argocd-applicationset-controller -n argocd --replicas=0

# Or delete it entirely if you don't need it
kubectl delete deployment argocd-applicationset-controller -n argocd --ignore-not-found=true
```

## Verify the Fix

After applying the fix:

```bash
# Check ArgoCD controller logs - errors should stop
kubectl logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=50

# Verify ApplicationSet controller status
kubectl get deployment argocd-applicationset-controller -n argocd 2>/dev/null || echo "ApplicationSet controller not found (this is OK if disabled)"
```

## Which Option Should You Choose?

- **Choose Option 1** if you want to manage multiple Applications declaratively using ApplicationSet
- **Choose Option 2** if you're managing Applications individually (like you're doing now) and don't need ApplicationSet features

For your current setup with individual Applications, **Option 2 (disabling ApplicationSet)** is recommended.
