# Complete Kubernetes-Native CI/CD Setup

## Architecture Overview

```
┌─────────────────┐
│   Git Push       │
└────────┬─────────┘
         │
         ▼
┌─────────────────┐
│ Argo Workflows  │ ◄─── CI (Build, Test, Push)
│   (CI)          │
└────────┬────────┘
         │
         │ Updates Git with image tag
         ▼
┌─────────────────┐
│   Git Repo       │
└────────┬─────────┘
         │
         │ ArgoCD detects change
         ▼
┌─────────────────┐
│    ArgoCD       │ ◄─── CD (Deploy to K8s)
│     (CD)        │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│   Kubernetes    │
│    Cluster      │
└─────────────────┘
```

## Complete Stack

1. **Argo Workflows** - CI (Build, Test, Push images)
2. **ArgoCD** - CD (GitOps deployment) - ✅ Already set up!
3. **Argo Rollouts** - Advanced deployment strategies (optional)

## Quick Start

### Step 1: Install Argo Workflows

```bash
cd /Volumes/X9Pro/Labs/uabsd/argo-labs
chmod +x workflows/install.sh
./workflows/install.sh
```

Or manually:
```bash
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.5/install.yaml
```

### Step 2: Test with Simple Workflow

```bash
# Submit a test workflow
argo submit -n argo workflows/simple-build-test.yaml

# Watch it run
argo watch -n argo @latest

# Access UI
kubectl -n argo port-forward svc/argo-server 2746:2746
# Open https://localhost:2746
```

### Step 3: Integrate with Your ArgoCD Setup

Your ArgoCD Applications (`argocd-applications.yaml`) will automatically pick up changes when:
- Argo Workflows updates image tags in Git
- ArgoCD detects the Git change
- ArgoCD syncs and deploys

## Workflow: Complete CI/CD Pipeline

### Scenario: Build and Deploy Your Vote App

1. **Developer pushes code** to `main` branch
2. **Argo Workflows triggers** (via webhook or manual)
3. **CI Pipeline runs**:
   ```yaml
   - Checkout code
   - Build Docker image (vote:v1.2.3)
   - Run tests
   - Push to registry
   - Update base/kustomization.yaml with new image tag
   - Commit and push to Git
   ```
4. **ArgoCD detects change** in Git
5. **ArgoCD syncs** and deploys to staging/prod

## Example: End-to-End Workflow

### 1. Create Workflow that Updates Git

```yaml
# workflows/build-and-update-git.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: build-vote-app-
spec:
  entrypoint: build-and-update
  templates:
  - name: build-and-update
    steps:
    - - name: build-image
        template: docker-build
    - - name: push-image
        template: docker-push
    - - name: update-git
        template: update-kustomization
        arguments:
          parameters:
          - name: image-tag
            value: "{{workflow.name}}"
```

### 2. Workflow Updates Your Kustomization

The workflow updates `base/kustomization.yaml` or your image references:

```yaml
# In workflow step
- name: update-kustomization
  container:
    image: alpine/git:latest
    command: [sh, -c]
    args:
    - |
      git clone https://github.com/gilsonbellon/argo-labs.git
      cd argo-labs
      # Update image in base/rollout.yaml or wherever your image is defined
      sed -i "s|image:.*vote.*|image: schoolofdevops/vote:{{inputs.parameters.image-tag}}|g" base/rollout.yaml
      git add .
      git commit -m "CI: Update vote image to {{inputs.parameters.image-tag}}"
      git push
```

### 3. ArgoCD Automatically Deploys

Your existing ArgoCD Applications will:
- Detect the Git change
- Sync automatically (if `selfHeal: true`)
- Deploy to staging/prod namespaces

## Benefits Over Jenkins

| Feature | Jenkins | Argo Workflows |
|---------|---------|----------------|
| **Runs on K8s** | ❌ Needs agents | ✅ Native pods |
| **Scaling** | ❌ Manual | ✅ Automatic |
| **Resource usage** | ❌ High (idle agents) | ✅ Low (on-demand) |
| **Integration** | ❌ Separate tool | ✅ Works with ArgoCD |
| **GitOps** | ⚠️ Possible but complex | ✅ Native |

## Migration Path from Jenkins

### Phase 1: Parallel Run (1-2 weeks)
- Keep Jenkins running
- Set up Argo Workflows
- Run new projects on Argo Workflows
- Compare results

### Phase 2: Migrate Simple Pipelines (2-4 weeks)
- Migrate build/test pipelines
- Migrate simple deployments
- Document differences

### Phase 3: Full Migration (4-8 weeks)
- Migrate complex pipelines
- Set up webhooks/triggers
- Train team
- Decommission Jenkins

## Common Workflows

### Build and Test Only

```bash
argo submit -n argo workflows/simple-build-test.yaml
```

### Build, Push, and Update Git (Triggers ArgoCD)

```bash
argo submit -n argo workflows/ci-pipeline.yaml \
  -p repo-url=https://github.com/gilsonbellon/argo-labs.git \
  -p revision=main \
  -p image-name=vote-app
```

### Scheduled Nightly Builds

```yaml
apiVersion: argoproj.io/v1alpha1
kind: CronWorkflow
metadata:
  name: nightly-build
  namespace: argo
spec:
  schedule: "0 2 * * *"  # 2 AM daily
  workflowSpec:
    entrypoint: build-and-test
    # ... use your workflow template
```

## Webhook Integration (GitHub/GitLab)

### Option 1: Argo Events (Recommended)

Install Argo Events for event-driven workflows:

```bash
kubectl create namespace argo-events
kubectl apply -f https://raw.githubusercontent.com/argoproj/argo-events/stable/manifests/install.yaml
```

### Option 2: GitHub Actions

Use GitHub Actions to trigger Argo Workflows:

```yaml
# .github/workflows/trigger-argo.yaml
name: Trigger Argo Workflow
on:
  push:
    branches: [main]
jobs:
  trigger:
    runs-on: ubuntu-latest
    steps:
    - name: Trigger Argo Workflow
      run: |
        argo submit -n argo workflows/ci-pipeline.yaml
```

## Monitoring and Observability

### View Workflows

```bash
# List all workflows
argo list -n argo

# Get workflow details
argo get -n argo <workflow-name>

# View logs
argo logs -n argo <workflow-name>

# Watch live
argo watch -n argo <workflow-name>
```

### UI Access

```bash
# Port forward
kubectl -n argo port-forward svc/argo-server 2746:2746

# Or create ingress for production
```

### Integration with Prometheus/Grafana

Argo Workflows exposes metrics on `/metrics` endpoint.

## Troubleshooting

### Workflow Not Starting

```bash
# Check workflow controller
kubectl logs -n argo -l app=workflow-controller

# Check pods
kubectl get pods -n argo

# Check events
kubectl get events -n argo --sort-by='.lastTimestamp'
```

### Permission Issues

```bash
# Check service account
kubectl get sa -n argo

# Check RBAC
kubectl get role,rolebinding -n argo
```

### Integration Issues with ArgoCD

- Ensure Git credentials are configured
- Verify ArgoCD can access the repository
- Check ArgoCD sync status: `argocd app get staging-vote`

## Next Steps

1. ✅ Install Argo Workflows (`workflows/install.sh`)
2. ✅ Test with simple workflow
3. ✅ Create workflow for your vote app
4. ✅ Set up webhook triggers
5. ✅ Integrate with ArgoCD
6. ✅ Migrate from Jenkins gradually

## Resources

- [Argo Workflows Docs](https://argo-workflows.readthedocs.io/)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [Example Workflows](https://github.com/argoproj/argo-workflows/tree/master/examples)
- Your workflows: `workflows/` directory
