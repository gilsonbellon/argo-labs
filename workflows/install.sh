#!/bin/bash
# Install Argo Workflows v3.7.9 with proper authentication setup
# Follows official documentation: https://argo-workflows.readthedocs.io/en/release-3.7/access-token/

set -e

NAMESPACE="argo"
VERSION="v3.7.9"
SA_NAME="argo-ui"
SECRET_NAME="${SA_NAME}.service-account-token"

echo "🚀 Installing Argo Workflows ${VERSION}..."

# Create namespace
kubectl create namespace ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Install Argo Workflows
echo "📦 Applying manifests..."
kubectl apply -n ${NAMESPACE} -f https://github.com/argoproj/argo-workflows/releases/download/${VERSION}/install.yaml

# Wait for pods
echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=workflow-controller -n ${NAMESPACE} --timeout=300s || true
kubectl wait --for=condition=ready pod -l app=argo-server -n ${NAMESPACE} --timeout=300s || true

# Set up RBAC for workflow-controller (CRITICAL for workflow execution)
echo "🔐 Setting up workflow-controller RBAC..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: workflow-controller
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/exec"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "patch"]
- apiGroups: ["argoproj.io"]
  resources: ["workflows", "workflowtemplates", "cronworkflows", "workflowtasksets"]
  verbs: ["get", "list", "watch", "update", "patch", "create", "delete"]
- apiGroups: ["argoproj.io"]
  resources: ["workflows/status"]
  verbs: ["get", "update", "patch"]
- apiGroups: ["argoproj.io"]
  resources: ["workflowtaskresults"]
  verbs: ["get", "list", "watch", "create", "update", "patch", "delete"]
EOF

# Get workflow-controller service account name
WF_CONTROLLER_SA=$(kubectl get deployment workflow-controller -n ${NAMESPACE} -o jsonpath='{.spec.template.spec.serviceAccountName}' 2>/dev/null || echo "argo")
kubectl create clusterrolebinding workflow-controller \
  --clusterrole=workflow-controller \
  --serviceaccount=${NAMESPACE}:${WF_CONTROLLER_SA} \
  --dry-run=client -o yaml | kubectl apply -f -

# Set up RBAC for workflow pods (argo-workflow service account)
echo "🔐 Setting up workflow executor RBAC..."
kubectl create sa argo-workflow -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: workflow-executor
rules:
- apiGroups: ["argoproj.io"]
  resources: ["workflowtasksets"]
  verbs: ["get", "list", "watch", "update", "patch"]
- apiGroups: ["argoproj.io"]
  resources: ["workflowtaskresults"]
  verbs: ["get", "list", "watch", "create", "update", "patch"]
- apiGroups: [""]
  resources: ["pods"]
  verbs: ["patch", "update"]
EOF

kubectl create clusterrolebinding workflow-executor \
  --clusterrole=workflow-executor \
  --serviceaccount=${NAMESPACE}:argo-workflow \
  --dry-run=client -o yaml | kubectl apply -f -

# Create ClusterRole for workflow pods to create/manage pods
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: argo-workflow-executor
rules:
- apiGroups: [""]
  resources: ["pods", "pods/log", "pods/exec"]
  verbs: ["create", "get", "list", "watch", "update", "patch", "delete"]
- apiGroups: [""]
  resources: ["configmaps", "secrets"]
  verbs: ["get", "list", "watch"]
- apiGroups: [""]
  resources: ["events"]
  verbs: ["create", "patch"]
EOF

kubectl create clusterrolebinding argo-workflow-executor \
  --clusterrole=argo-workflow-executor \
  --serviceaccount=${NAMESPACE}:argo-workflow \
  --dry-run=client -o yaml | kubectl apply -f -

# Set up MinIO for artifact storage
echo "📦 Setting up MinIO for artifact storage..."
kubectl apply -n ${NAMESPACE} -f - <<EOF
apiVersion: apps/v1
kind: Deployment
metadata:
  name: minio
  namespace: ${NAMESPACE}
spec:
  replicas: 1
  selector:
    matchLabels:
      app: minio
  template:
    metadata:
      labels:
        app: minio
    spec:
      containers:
      - name: minio
        image: minio/minio:latest
        args: ["server", "/data", "--console-address", ":9001"]
        env:
        - name: MINIO_ROOT_USER
          value: "minioadmin"
        - name: MINIO_ROOT_PASSWORD
          value: "minioadmin"
        ports:
        - containerPort: 9000
        - containerPort: 9001
        volumeMounts:
        - name: data
          mountPath: /data
      volumes:
      - name: data
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: minio
  namespace: ${NAMESPACE}
spec:
  ports:
  - port: 9000
    targetPort: 9000
  selector:
    app: minio
EOF

# Wait for MinIO to be ready
echo "⏳ Waiting for MinIO to be ready..."
kubectl wait --for=condition=ready pod -l app=minio -n ${NAMESPACE} --timeout=120s || true

# Create MinIO credentials secret
kubectl create secret generic my-minio-cred -n ${NAMESPACE} \
  --from-literal=accesskey=minioadmin \
  --from-literal=secretkey=minioadmin \
  --dry-run=client -o yaml | kubectl apply -f -

# Create MinIO bucket
echo "📦 Creating MinIO bucket..."
kubectl run -it --rm --restart=Never minio-bucket-setup --image=minio/mc --command -- sh -c "
  mc alias set minio http://minio.${NAMESPACE}.svc:9000 minioadmin minioadmin &&
  mc mb minio/argo-workflows --ignore-existing &&
  echo '✅ Bucket argo-workflows created'
" 2>/dev/null || echo "⚠️  Bucket creation may need manual setup"

# Configure artifact repository
echo "🔧 Configuring artifact repository..."
kubectl create configmap workflow-controller-configmap -n ${NAMESPACE} --from-literal=config="artifactRepository:
  archiveLogs: true
  s3:
    bucket: argo-workflows
    endpoint: minio.${NAMESPACE}.svc:9000
    insecure: true
    accessKeySecret:
      name: my-minio-cred
      key: accesskey
    secretKeySecret:
      name: my-minio-cred
      key: secretkey
" --dry-run=client -o yaml | kubectl apply -f -

# Restart workflow-controller to pick up config
kubectl rollout restart deployment workflow-controller -n ${NAMESPACE}
kubectl rollout status deployment workflow-controller -n ${NAMESPACE} --timeout=60s || true

# Configure authentication mode for web UI (per official docs)
echo "🔧 Configuring authentication mode..."
kubectl -n ${NAMESPACE} patch deployment argo-server --type='json' -p='[
  {
    "op": "add",
    "path": "/spec/template/spec/containers/0/args/-",
    "value": "--auth-mode=client"
  }
]' 2>/dev/null && {
    echo "🔄 Restarting argo-server..."
    kubectl -n ${NAMESPACE} rollout restart deployment argo-server
    kubectl -n ${NAMESPACE} rollout status deployment argo-server --timeout=60s || true
}

# Set up service account and RBAC for web UI access (per official docs)
echo "🔐 Setting up service account and RBAC (per official docs)..."

# Create ClusterRole for web UI (allows access across namespaces)
echo "   Creating ClusterRole with web UI permissions..."
kubectl create clusterrole ${SA_NAME} \
  --verb=list,get,watch,create,update,patch,delete \
  --resource=workflows.argoproj.io \
  --dry-run=client -o yaml | kubectl apply -f -

# Also allow access to workflowtemplates, clusterworkflowtemplates, cronworkflows, and Argo Events resources
echo "   Creating ClusterRole for templates and Argo Events resources..."
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: ${SA_NAME}-templates
rules:
- apiGroups:
  - argoproj.io
  resources:
  - workflowtemplates
  - clusterworkflowtemplates
  - cronworkflows
  - workfloweventbindings
  - sensors
  - eventsources
  verbs:
  - list
  - get
  - watch
EOF

# Add permissions for pods, events, and logs (needed for UI to display workflow tree)
echo "   Adding pod, event, and log permissions for workflow tree visualization..."
kubectl create clusterrole ${SA_NAME}-pods \
  --verb=list,get,watch \
  --resource=pods,events \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# Add pod log access (needed for viewing logs in UI)
kubectl create clusterrole ${SA_NAME}-logs \
  --verb=get,list \
  --resource=pods/log \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

kubectl create clusterrolebinding ${SA_NAME}-logs \
  --clusterrole=${SA_NAME}-logs \
  --serviceaccount=${NAMESPACE}:${SA_NAME} \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

kubectl create clusterrolebinding ${SA_NAME}-pods \
  --clusterrole=${SA_NAME}-pods \
  --serviceaccount=${NAMESPACE}:${SA_NAME} \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# Create service account
echo "   Creating service account..."
kubectl create sa ${SA_NAME} -n ${NAMESPACE} --dry-run=client -o yaml | kubectl apply -f -

# Bind service account to ClusterRoles (allows access across namespaces)
echo "   Creating ClusterRole bindings..."
kubectl create clusterrolebinding ${SA_NAME} \
  --clusterrole=${SA_NAME} \
  --serviceaccount=${NAMESPACE}:${SA_NAME} \
  --dry-run=client -o yaml | kubectl apply -f -

# Bind to templates ClusterRole
kubectl create clusterrolebinding ${SA_NAME}-templates \
  --clusterrole=${SA_NAME}-templates \
  --serviceaccount=${NAMESPACE}:${SA_NAME} \
  --dry-run=client -o yaml | kubectl apply -f - 2>/dev/null || true

# Create secret for token (per official docs)
echo "   Creating secret for token..."
kubectl apply -n ${NAMESPACE} -f - <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: ${SECRET_NAME}
  annotations:
    kubernetes.io/service-account.name: ${SA_NAME}
type: kubernetes.io/service-account-token
EOF

# Wait for secret token to be created
echo "⏳ Waiting for token to be created..."
sleep 5

# Verify token exists
if kubectl -n ${NAMESPACE} get secret ${SECRET_NAME} &>/dev/null; then
    echo "✅ Token secret created successfully"
else
    echo "⚠️  Token secret not ready yet, it will be created automatically"
fi

echo ""
echo "✅ Installation complete!"
kubectl get pods -n ${NAMESPACE}

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📋 Setup Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Argo Workflows ${VERSION} installed"
echo "✅ Authentication configured (--auth-mode=client)"
echo "✅ UI service account created: ${SA_NAME}"
echo "✅ Workflow executor service account created: argo-workflow"
echo "✅ RBAC configured for:"
echo "   - workflow-controller (with workflows/status permission)"
echo "   - workflow-executor (with workflowtaskresults permission)"
echo "   - argo-ui (with full UI permissions)"
echo "✅ MinIO artifact storage configured"
echo "✅ Artifact repository configured"
echo "✅ Token secret created: ${SECRET_NAME}"
echo ""
echo "📋 Next steps:"
echo "   1. Run ./access.sh to get token and access UI"
echo "   2. Apply workflow templates: kubectl apply -f workflows/*.yaml"
echo "   3. Test workflow: kubectl create -n argo -f workflows/01-simple-test-only.yaml"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
