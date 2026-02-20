# Using kubectl with Argo Workflows

This guide shows how to use `kubectl` instead of the `argo` CLI to work with Argo Workflows.

## Prerequisites

- `kubectl` configured to access your Kubernetes cluster
- Argo Workflows installed in your cluster
- Access to the `argo` namespace (or your workflow namespace)

## 1. Apply WorkflowTemplate

First, apply the WorkflowTemplate to make it available:

```bash
kubectl apply -f 06-database-operations.yaml -n argo
```

Verify it was created:

```bash
kubectl get workflowtemplate -n argo
kubectl get workflowtemplate database-operations -n argo -o yaml
```

## 2. Submit a Workflow from Template

### Option A: Using a Workflow manifest (Recommended)

Create a Workflow manifest that references the WorkflowTemplate:

```bash
kubectl apply -f 06-database-operations-example-workflow.yaml -n argo
```

Or create your own workflow file:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: database-operations-  # Will create: database-operations-xxxxx
  namespace: argo
spec:
  workflowTemplateRef:
    name: database-operations
  arguments:
    parameters:
    - name: db-host
      value: "postgresql.default.svc.cluster.local"
    - name: db-admin-password
      value: "your-password-here"
    - name: new-username
      value: "appuser"
```

### Option B: Using kubectl create with inline YAML

```bash
kubectl create -n argo -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: database-operations-
  namespace: argo
spec:
  workflowTemplateRef:
    name: database-operations
  arguments:
    parameters:
    - name: db-admin-password
      value: "your-password-here"
    - name: new-username
      value: "appuser"
EOF
```

### Option C: Using kubectl patch (if you have an existing workflow)

```bash
# First create a minimal workflow
kubectl create -n argo -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  name: database-operations-test
  namespace: argo
spec:
  workflowTemplateRef:
    name: database-operations
EOF

# Then patch it with parameters
kubectl patch workflow database-operations-test -n argo --type merge -p '
{
  "spec": {
    "arguments": {
      "parameters": [
        {"name": "db-admin-password", "value": "your-password"},
        {"name": "new-username", "value": "appuser"}
      ]
    }
  }
}'
```

## 3. Monitor Workflow Status

### List all workflows:

```bash
kubectl get workflows -n argo
```

### Watch workflows:

```bash
kubectl get workflows -n argo -w
```

### Get specific workflow details:

```bash
# Get workflow status
kubectl get workflow <workflow-name> -n argo

# Get full workflow YAML
kubectl get workflow <workflow-name> -n argo -o yaml

# Get workflow status in JSON (useful for automation)
kubectl get workflow <workflow-name> -n argo -o jsonpath='{.status.phase}'
```

### Check workflow logs:

```bash
# List pods created by the workflow
kubectl get pods -n argo -l workflows.argoproj.io/workflow=<workflow-name>

# Get logs from a specific step
kubectl logs <pod-name> -n argo

# Follow logs
kubectl logs -f <pod-name> -n argo
```

## 4. Common Operations

### Delete a workflow:

```bash
kubectl delete workflow <workflow-name> -n argo
```

### Delete all completed workflows:

```bash
kubectl delete workflows -n argo --field-selector status.phase=Succeeded
kubectl delete workflows -n argo --field-selector status.phase=Failed
```

### Suspend a running workflow:

```bash
kubectl patch workflow <workflow-name> -n argo --type merge -p '{"spec":{"suspend":true}}'
```

### Resume a suspended workflow:

```bash
kubectl patch workflow <workflow-name> -n argo --type merge -p '{"spec":{"suspend":null}}'
```

### Retry a failed workflow:

```bash
kubectl patch workflow <workflow-name> -n argo --type merge -p '{"spec":{"retryStrategy":{"limit":3}}}'
```

## 5. Using Secrets for Passwords

Instead of putting passwords in the workflow manifest, use Kubernetes secrets:

### Create a secret:

```bash
kubectl create secret generic db-admin-secret \
  -n argo \
  --from-literal=password="your-secure-password"
```

### Reference secret in workflow:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: database-operations-
  namespace: argo
spec:
  workflowTemplateRef:
    name: database-operations
  arguments:
    parameters:
    - name: db-admin-password
      valueFrom:
        secretKeyRef:
          name: db-admin-secret
          key: password
```

**Note:** Argo Workflows doesn't directly support `valueFrom.secretKeyRef` in parameters. Instead, you'll need to:

1. Pass the secret value when creating the workflow:

```bash
DB_PASSWORD=$(kubectl get secret db-admin-secret -n argo -o jsonpath='{.data.password}' | base64 -d)

kubectl create -n argo -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: database-operations-
spec:
  workflowTemplateRef:
    name: database-operations
  arguments:
    parameters:
    - name: db-admin-password
      value: "${DB_PASSWORD}"
EOF
```

2. Or modify the WorkflowTemplate to use environment variables from secrets (more advanced).

## 6. Quick Reference

| Task | Command |
|------|---------|
| Apply template | `kubectl apply -f 06-database-operations.yaml -n argo` |
| List templates | `kubectl get workflowtemplate -n argo` |
| Submit workflow | `kubectl apply -f workflow.yaml -n argo` |
| List workflows | `kubectl get workflows -n argo` |
| Get workflow status | `kubectl get workflow <name> -n argo` |
| Get workflow logs | `kubectl logs <pod-name> -n argo` |
| Delete workflow | `kubectl delete workflow <name> -n argo` |
| Watch workflows | `kubectl get workflows -n argo -w` |

## 7. Example: Complete Workflow

Here's a complete example workflow file you can customize:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: database-operations-
  namespace: argo
spec:
  workflowTemplateRef:
    name: database-operations
  arguments:
    parameters:
    - name: db-host
      value: "postgresql.default.svc.cluster.local"
    - name: db-port
      value: "5432"
    - name: db-name
      value: "testdb"
    - name: db-admin-user
      value: "postgres"
    - name: db-admin-password
      value: "your-password-here"  # Replace with actual password
    - name: new-username
      value: "appuser"
    - name: new-user-password
      value: ""  # Empty = auto-generate
    - name: new-user-database
      value: "testdb"
    - name: custom-query
      value: "SELECT COUNT(*) FROM pg_stat_activity;"
```

Save this as `my-database-workflow.yaml` and apply:

```bash
kubectl apply -f my-database-workflow.yaml -n argo
```

## Troubleshooting

### Workflow stays in "Pending" state:
- Check if the namespace exists: `kubectl get namespace argo`
- Check workflow controller logs: `kubectl logs -n argo -l app=workflow-controller`

### Workflow fails immediately:
- Check workflow events: `kubectl describe workflow <name> -n argo`
- Check workflow status: `kubectl get workflow <name> -n argo -o yaml`

### Can't connect to database:
- Verify database hostname is correct (use FQDN: `service.namespace.svc.cluster.local`)
- Check network policies allow access from `argo` namespace
- Verify database credentials are correct
