# How to Run Workflow Templates

This guide shows you how to run your WorkflowTemplates using only `kubectl` (no local Argo CLI needed).

## Quick Start

### Step 1: Apply WorkflowTemplates (one-time setup)

Apply all templates to your cluster:

```bash
cd /Volumes/X9Pro/Labs/uabsd/argo-labs/workflows

kubectl apply -n argo -f 01-simple-test-only.yaml
kubectl apply -n argo -f 02-moderate-build-test.yaml
kubectl apply -n argo -f 03-complex-quality-pipeline.yaml
kubectl apply -n argo -f 04-harbor-build-push.yaml
kubectl apply -n argo -f simple-build-test.yaml
```

### Step 2: Create and Run Workflows

To run a template, create a `Workflow` resource that references it. Here are ready-to-use commands:

---

## 1. Simple Test Only (`simple-test-only`)

**Purpose:** Runs unit tests only (no build, no push)

```bash
kubectl create -n argo -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: simple-test-
  namespace: argo
spec:
  entrypoint: test-only
  workflowTemplateRef:
    name: simple-test-only
  arguments:
    parameters:
      - name: repo-url
        value: "https://github.com/gilsonbellon/argo-labs.git"
      - name: revision
        value: "main"
EOF
```

**Monitor:**
```bash
kubectl get workflows -n argo
kubectl logs -n argo -f <workflow-name>
```

---

## 2. Moderate Build Test (`moderate-build-test`)

**Purpose:** Builds Docker image and runs tests (no push)

```bash
kubectl create -n argo -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: moderate-build-
  namespace: argo
spec:
  entrypoint: build-and-test
  workflowTemplateRef:
    name: moderate-build-test
  arguments:
    parameters:
      - name: repo-url
        value: "https://github.com/gilsonbellon/argo-labs.git"
      - name: revision
        value: "main"
      - name: image-name
        value: "my-app"
EOF
```

---

## 3. Complex Quality Pipeline (`complex-quality-pipeline`)

**Purpose:** Runs comprehensive quality checks (no build, no push)

```bash
kubectl create -n argo -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: quality-pipeline-
  namespace: argo
spec:
  entrypoint: quality-pipeline
  workflowTemplateRef:
    name: complex-quality-pipeline
  arguments:
    parameters:
      - name: repo-url
        value: "https://github.com/gilsonbellon/argo-labs.git"
      - name: revision
        value: "main"
EOF
```

---

## 4. Harbor Build & Push (`harbor-build-push`)

**Purpose:** Builds Docker image and pushes to Harbor registry

**Option A: Using Kubernetes Secret (Recommended)**

First, create the Harbor secret:
```bash
kubectl create secret generic harbor-credentials \
  -n argo \
  --from-literal=username=admin \
  --from-literal=password=your-password
```

Then run the workflow:
```bash
kubectl create -n argo -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: harbor-push-
  namespace: argo
spec:
  entrypoint: harbor-build-push
  workflowTemplateRef:
    name: harbor-build-push
  arguments:
    parameters:
      - name: repo-url
        value: "https://github.com/gilsonbellon/argo-labs.git"
      - name: revision
        value: "main"
      - name: repository
        value: "my-app"
      - name: tag
        value: "v1.0.0-$(date +%s)"
EOF
```

**Option B: Passing credentials as parameters**

```bash
kubectl create -n argo -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: harbor-push-
  namespace: argo
spec:
  entrypoint: harbor-build-push
  workflowTemplateRef:
    name: harbor-build-push
  arguments:
    parameters:
      - name: repo-url
        value: "https://github.com/gilsonbellon/argo-labs.git"
      - name: revision
        value: "main"
      - name: repository
        value: "my-app"
      - name: tag
        value: "v1.0.0-$(date +%s)"
      - name: harbor-username
        value: "admin"
      - name: harbor-password
        value: "your-password"
EOF
```

---

## 5. Simple Build Test (`simple-build-test`)

**Purpose:** Simple build and test workflow (no push)

```bash
kubectl create -n argo -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: simple-build-test-
  namespace: argo
spec:
  entrypoint: build-and-test
  workflowTemplateRef:
    name: simple-build-test
  arguments:
    parameters:
      - name: repo-url
        value: "https://github.com/gilsonbellon/argo-labs.git"
      - name: revision
        value: "main"
      - name: image-name
        value: "my-simple-app"
EOF
```

---

## Monitoring Workflows

### List all workflows:
```bash
kubectl get workflows -n argo
```

### View workflow details:
```bash
kubectl get workflow <workflow-name> -n argo -o yaml
```

### View workflow logs:
```bash
kubectl logs -n argo <workflow-name>
```

### Watch workflow status:
```bash
watch kubectl get workflows -n argo
```

### Access Web UI:
```bash
cd /Volumes/X9Pro/Labs/uabsd/argo-labs/workflows
./access.sh
```
Then open `https://localhost:2746` in your browser.

---

## Tips

1. **Workflow Names:** Each workflow gets a unique name with a random suffix (e.g., `simple-test-abc123`)
2. **Parameters:** You can override any parameter by changing the `value` in the workflow YAML
3. **Tag Auto-generation:** The Harbor template uses `{{workflow.name}}` for tags, which creates unique tags automatically
4. **Cleanup:** Completed workflows remain in the cluster. To delete:
   ```bash
   kubectl delete workflow <workflow-name> -n argo
   ```

---

## Troubleshooting

### Check if templates are applied:
```bash
kubectl get workflowtemplates -n argo
```

### View template details:
```bash
kubectl get workflowtemplate <template-name> -n argo -o yaml
```

### Check workflow pod status:
```bash
kubectl get pods -n argo -l workflows.argoproj.io/workflow
```

### View pod logs:
```bash
kubectl logs -n argo <pod-name>
```
