# Helm-Based Deployments

This directory contains Helm chart-based deployments for the vote application, created as an alternative to the Kustomize-based deployments.

## Structure

```
helm-deployments/
├── vote-chart/              # Helm chart for vote application
│   ├── Chart.yaml          # Chart metadata
│   ├── values.yaml         # Default values
│   └── templates/         # Kubernetes manifests
│       ├── rollout.yaml
│       ├── service.yaml
│       ├── preview-service.yaml
│       └── ingress.yaml
├── staging-values.yaml      # Staging environment overrides
├── prod-values.yaml         # Production environment overrides
├── argocd-applications-helm.yaml  # ArgoCD Applications using Helm
└── README.md               # This file
```

## Differences from Kustomize Version

### Kustomize Version (existing)
- Location: `base/`, `staging/`, `prod/`
- Uses: Kustomize overlays and patches
- ArgoCD Applications: `staging-vote`, `prod-vote` (in `argocd-applications.yaml`)

### Helm Version (this directory)
- Location: `helm-deployments/`
- Uses: Helm charts with values files
- ArgoCD Applications: `staging-vote-helm`, `prod-vote-helm` (in `argocd-applications-helm.yaml`)

## Features

- **Same functionality**: Both versions deploy the same vote application
- **Parallel deployment**: Can coexist without conflicts (different namespaces/names)
- **Helm benefits**: 
  - Better parameterization
  - Easier version management
  - Template reusability
  - Values file overrides

## Usage

### Deploy ArgoCD Applications (Helm-based)

```bash
# Apply the Helm-based ArgoCD Applications
kubectl apply -f helm-deployments/argocd-applications-helm.yaml
```

### Manual Helm Install (for testing)

```bash
# Install staging
helm install staging-vote ./vote-chart \
  -f staging-values.yaml \
  -n staging \
  --create-namespace

# Install production
helm install prod-vote ./vote-chart \
  -f prod-values.yaml \
  -n prod \
  --create-namespace
```

### Update Values

Edit the values files:
- `staging-values.yaml` - for staging environment
- `prod-values.yaml` - for production environment

Then sync via ArgoCD UI or:

```bash
# ArgoCD will auto-sync if automated sync is enabled
# Or manually sync:
argocd app sync staging-vote-helm
argocd app sync prod-vote-helm
```

## Configuration

### Staging Environment
- Strategy: Blue-Green
- Replicas: 1
- Service: NodePort (30000)
- Preview Service: NodePort (30100)
- Ingress: Disabled

### Production Environment
- Strategy: Canary
- Replicas: 5
- Service: NodePort (30200)
- Preview Service: NodePort (30300)
- Ingress: Enabled (vote.example.com)

## Important Notes

⚠️ **These Helm-based applications are NOT applied by default**

- The ArgoCD Applications use different names (`staging-vote-helm`, `prod-vote-helm`)
- They deploy to the same namespaces but can coexist with Kustomize versions
- To use them, explicitly apply `argocd-applications-helm.yaml`
- The Kustomize versions (`staging-vote`, `prod-vote`) remain unchanged

### ArgoCD ValueFiles Path Configuration

The `valueFiles` in ArgoCD Applications are configured to use paths relative to the repository root:
- `helm-deployments/staging-values.yaml`
- `helm-deployments/prod-values.yaml`

If ArgoCD has issues resolving these paths, you may need to adjust them to be relative to the chart directory (`../staging-values.yaml`). This depends on your ArgoCD version and configuration.

## Testing

To test the Helm version without affecting Kustomize:

1. Apply Helm-based ArgoCD Applications:
   ```bash
   kubectl apply -f helm-deployments/argocd-applications-helm.yaml
   ```

2. Check in ArgoCD UI - you'll see both:
   - `staging-vote` (Kustomize)
   - `staging-vote-helm` (Helm)

3. They deploy to the same namespace but use different resource names/selectors if needed

4. To remove Helm version:
   ```bash
   kubectl delete -f helm-deployments/argocd-applications-helm.yaml
   ```
