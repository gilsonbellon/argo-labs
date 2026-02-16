# Argo Workflows Setup Guide - Kubernetes-Native CI/CD

## Why Argo Workflows for Kubernetes

- ✅ **100% Kubernetes-native** - Everything runs as pods
- ✅ **No external agents** - No Jenkins masters/agents to manage
- ✅ **Automatic scaling** - Scales with your cluster
- ✅ **Integrates with ArgoCD** - Complete GitOps workflow
- ✅ **Resource efficient** - Pods created/destroyed on demand

## Installation

### Step 1: Install Argo Workflows

```bash
# Create namespace
kubectl create namespace argo

# Install Argo Workflows
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.0/install.yaml

# Or use a specific version (check latest at https://github.com/argoproj/argo-workflows/releases)
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.5/install.yaml
```

### Step 2: Install Argo Workflows CLI (Optional but Recommended)

**macOS:**
```bash
brew install argo-workflows
```

**Linux:**
```bash
# Download latest
curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.5.5/argo-linux-amd64.gz
gunzip argo-linux-amd64.gz
chmod +x argo-linux-amd64
sudo mv argo-linux-amd64 /usr/local/bin/argo
```

**Windows:**
Download from: https://github.com/argoproj/argo-workflows/releases

### Step 3: Verify Installation

```bash
# Check pods
kubectl get pods -n argo

# Check CRDs
kubectl get crd | grep workflows

# Test CLI (if installed)
argo version
```

### Step 4: Configure RBAC (if needed)

If you need to submit workflows from CI/CD or other services, you may need to configure RBAC. The default installation should work for manual submissions.

## Access Argo Workflows UI

### Option 1: Port Forward (Quick Test)

```bash
kubectl -n argo port-forward svc/argo-server 2746:2746
```

Then access: https://localhost:2746

### Option 2: Ingress (Production)

Create an ingress resource for the Argo Workflows UI.

## Basic Workflow Example

See `workflows/ci-pipeline.yaml` for a complete example.

## Integration with ArgoCD

The typical flow:
1. **Argo Workflows** (CI): Build, test, build Docker images
2. **Push to registry**: Push images to container registry
3. **Update Git**: Update image tags in Git (via workflow)
4. **ArgoCD** (CD): Automatically detects changes and deploys

See `workflows/ci-cd-integration.yaml` for an example.

## Next Steps

1. Review the example workflows in `workflows/` directory
2. Customize for your use case
3. Set up webhook triggers (GitHub/GitLab)
4. Integrate with your ArgoCD setup
