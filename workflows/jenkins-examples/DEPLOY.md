# How to Deploy Jenkins-Migrated Workflows

## Quick Deploy

Deploy both workflow templates:

```bash
# Deploy IoT Build & Push workflow
kubectl apply -f jenkins-iot-build-push.yaml

# Deploy Helm Charts CI workflow
kubectl apply -f jenkins-helm-charts-ci.yaml
```

Or deploy all at once:

```bash
kubectl apply -f jenkins-examples/
```

## Verify Deployment

```bash
# List all Jenkins-migrated templates
kubectl get workflowtemplate -n argo | grep jenkins

# Check specific template
kubectl get workflowtemplate jenkins-iot-build-push -n argo
kubectl get workflowtemplate jenkins-helm-charts-ci -n argo
```

## How to Use

### 1. IoT Build & Push Workflow

Submit a workflow from the template:

```bash
kubectl create workflow -n argo \
  --from=workflowtemplate/jenkins-iot-build-push \
  -p app-repo="https://github.com/your-org/your-repo.git" \
  -p app-path="./app" \
  -p app-prefix="myapp" \
  -p app-branch="main" \
  -p app-env="staging" \
  -p hash-commit="HEAD"
```

Or via Argo Workflows UI:
1. Go to Workflow Templates
2. Find `jenkins-iot-build-push`
3. Click "Submit" and fill in parameters

### 2. Helm Charts CI Workflow

Submit a workflow from the template:

```bash
kubectl create workflow -n argo \
  --from=workflowtemplate/jenkins-helm-charts-ci \
  -p repo-url="https://github.com/your-org/helm-charts.git" \
  -p source-branch="feature/new-chart" \
  -p target-branch="main"
```

## Parameters

### jenkins-iot-build-push.yaml

| Parameter | Description | Default |
|-----------|-------------|---------|
| `app-repo` | Git repository URL | `https://bitbucket.org/ngpemsdevs/data-pipelines-new.git` |
| `app-path` | Path to application in repo | `.` |
| `app-prefix` | Application name prefix | `example-app` |
| `app-branch` | Git branch to checkout | `main` |
| `app-env` | Environment (staging/preprod/test) | `staging` |
| `hash-commit` | Commit hash for tagging | `HEAD` |
| `npm-token` | NPM token for build args (optional) | `` |

### jenkins-helm-charts-ci.yaml

| Parameter | Description | Default |
|-----------|-------------|---------|
| `repo-url` | Helm charts repository URL | `https://bitbucket.org/ngpemsdevs/helm-charts.git` |
| `source-branch` | Source branch (PR branch) | `feature/example` |
| `target-branch` | Target branch (base branch) | `main` |

## Requirements

- **Harbor credentials**: Secret `harbor-credentials` must exist in `argo` namespace
- **Service Account**: Uses `argo-workflow` service account (already exists)
- **For Helm charts**: Requires `ci-k8s-tools` image with helm, yamllint, kubeconform

## Example: Submit via Argo CLI

```bash
# IoT Build example
argo submit --from=workflowtemplate/jenkins-iot-build-push \
  -p app-repo="https://github.com/gilsonbellon/argo-labs.git" \
  -p app-path="." \
  -p app-prefix="vote" \
  -p app-branch="main" \
  -p app-env="staging" \
  -n argo

# Helm Charts CI example
argo submit --from=workflowtemplate/jenkins-helm-charts-ci \
  -p repo-url="https://github.com/your-org/helm-charts.git" \
  -p source-branch="feature/new-feature" \
  -p target-branch="main" \
  -n argo
```

## Notes

- These templates are **separate** from your existing workflows
- They use the same Harbor registry and secrets as your other workflows
- Adjust parameters to match your repositories and requirements
- The Helm charts workflow requires the `ci-k8s-tools` image to be available
