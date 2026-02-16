# Kustomize Deployment Guide

## Understanding the Error

The error message:
```
The Kubernetes API could not find kustomize.config.k8s.io/Kustomization for requested resource staging/
```

This error occurs when you try to apply `kustomization.yaml` files directly with `kubectl apply -f`. These files are **configuration files** for the Kustomize tool, not Kubernetes resources themselves.

## Solution: Use the Correct Commands

### Option 1: Using kubectl's Built-in Kustomize Support (Recommended)

Kubectl has built-in Kustomize support. Use the `-k` flag:

```bash
# Apply staging environment
kubectl apply -k staging/

# Apply production environment
kubectl apply -k prod/

# Preview what would be applied (dry-run)
kubectl apply -k staging/ --dry-run=client -o yaml
```

### Option 2: Using kustomize CLI Tool

If you have the `kustomize` CLI tool installed:

```bash
# Build and apply staging
kustomize build staging/ | kubectl apply -f -

# Build and apply production
kustomize build prod/ | kubectl apply -f -

# Preview the output
kustomize build staging/
```

### Option 3: If Using Flux CD

If you're using Flux CD for GitOps, you need to:

1. **Install Flux CD** (if not already installed):
   ```bash
   flux install
   ```

2. **Create a Flux Kustomization CRD** instead of applying the kustomization.yaml directly:
   
   Create a file like `flux-kustomization.yaml`:
   ```yaml
   apiVersion: kustomize.toolkit.fluxcd.io/v1
   kind: Kustomization
   metadata:
     name: staging
     namespace: flux-system
   spec:
     path: ./staging
     prune: true
     interval: 10m
     sourceRef:
       kind: GitRepository
       name: your-repo-name
   ```

3. **Apply the Flux Kustomization CRD**:
   ```bash
   kubectl apply -f flux-kustomization.yaml
   ```

### Option 4: If Using ArgoCD

ArgoCD automatically detects and uses `kustomization.yaml` files. However, you need to configure the ArgoCD Application correctly:

**Important**: The `path` in the Application must be **relative to the repository root** and point to the directory containing the `kustomization.yaml` file, NOT the file itself.

1. **Create an ArgoCD Application** pointing to your repository (see `argocd-applications.yaml` for examples)
2. **Ensure the path is correct** - it should be relative to the Git repository root
3. ArgoCD will automatically detect and use the `kustomization.yaml` files

**Common Issues:**
- ❌ Wrong: `path: uabsd/argo-labs/staging/kustomization.yaml` (points to file)
- ❌ Wrong: `path: uabsd/argo-labs/staging` (if repo root is `uabsd/argo-labs`)
- ✅ Correct: `path: staging` (if repository root is `uabsd/argo-labs`)

**If you still get the error**, try explicitly specifying the tool type:
```yaml
source:
  repoURL: https://github.com/your-org/your-repo
  targetRevision: HEAD
  path: staging  # Relative to repository root
  kustomize: {}  # Explicitly tell ArgoCD to use Kustomize
```

**How to determine the correct path:**
1. Find your Git repository root (where `.git` folder is located)
2. The path should be relative to that root
3. Example: If repo root is `uabsd/argo-labs` and staging is at `uabsd/argo-labs/staging`, use `path: staging`

See `argocd-applications.yaml` for complete examples.

## Current Structure

```
argo-labs/
├── base/              # Base configuration
│   ├── kustomization.yaml
│   ├── rollout.yaml
│   ├── service.yaml
│   └── preview-service.yaml
├── staging/           # Staging environment overlay
│   ├── kustomization.yaml
│   └── service.yaml
└── prod/              # Production environment overlay
    ├── kustomization.yaml
    ├── ingress.yaml
    ├── rollout.yaml
    ├── service.yaml
    └── preview-service.yaml
```

## Quick Reference

| Task | Command |
|------|---------|
| Apply staging | `kubectl apply -k staging/` |
| Apply production | `kubectl apply -k prod/` |
| Preview staging | `kubectl apply -k staging/ --dry-run=client -o yaml` |
| Delete staging | `kubectl delete -k staging/` |
| Validate kustomization | `kubectl kustomize staging/` |

## Troubleshooting

### Error: "Kustomization CRD is not installed" (ArgoCD)

If you see this error in ArgoCD, it usually means:

1. **Wrong path configuration**: The Application `path` should be **relative to the repository root** and point to the **directory** containing `kustomization.yaml`, not the file itself.
   ```yaml
   # ❌ Wrong - points to file
   path: staging/kustomization.yaml
   
   # ❌ Wrong - absolute path (if repo root is uabsd/argo-labs)
   path: uabsd/argo-labs/staging
   
   # ✅ Correct - relative to repository root
   path: staging
   ```

2. **ArgoCD not detecting Kustomize**: Explicitly specify Kustomize in your Application:
   ```yaml
   source:
     repoURL: https://github.com/your-org/your-repo
     path: uabsd/argo-labs/staging
     kustomize: {}  # Force ArgoCD to use Kustomize
   ```

3. **ArgoCD version compatibility**: Ensure you're using ArgoCD v2.0+ which fully supports Kustomize v4+.

4. **Check Application details in ArgoCD UI**: 
   - Go to the Application in ArgoCD UI
   - Check the "App Details" tab
   - Verify the "Source Type" shows "Kustomize" (not "Directory")

### Error: "no matches for kind 'Kustomization'"

This means you're trying to apply the `kustomization.yaml` file directly. Use `kubectl apply -k` instead of `kubectl apply -f`.

### ArgoCD Sync Issues

If ArgoCD shows "Unknown" or sync errors:

1. **Check the Application manifest** - ensure `path` points to the directory
2. **Verify repository access** - ArgoCD needs read access to your Git repo
3. **Check ArgoCD logs**:
   ```bash
   kubectl logs -n argocd -l app.kubernetes.io/name=argocd-repo-server
   ```
4. **Test Kustomize build locally**:
   ```bash
   kubectl kustomize staging/
   ```

### Other Common Issues

- **If using standard Kustomize**: This is normal - you don't need the CRD. Use `kubectl apply -k` instead of `kubectl apply -f`
- **If using Flux CD**: Install Flux CD with `flux install` to get the CRD
