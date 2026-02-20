#!/bin/bash
# Point Argo Workflows artifact repository at Garage (S3 endpoint).
# Run after install-garage.sh. Restarts workflow-controller.

set -e

ARGO_NAMESPACE="${ARGO_NAMESPACE:-argo}"
GARAGE_NAMESPACE="${GARAGE_NAMESPACE:-garage}"
GARAGE_SVC="${GARAGE_SVC:-garage}"
GARAGE_S3_PORT="${GARAGE_S3_PORT:-3900}"
BUCKET_NAME="${BUCKET_NAME:-argo-workflows}"
SECRET_NAME="${SECRET_NAME:-my-garage-cred}"

ENDPOINT="${GARAGE_SVC}.${GARAGE_NAMESPACE}.svc:${GARAGE_S3_PORT}"

echo "🔧 Configuring Argo Workflows to use Garage..."
echo "   Endpoint: ${ENDPOINT}"
echo "   Bucket: ${BUCKET_NAME}"
echo "   Secret: ${SECRET_NAME} (in ${ARGO_NAMESPACE})"
echo ""

# Multiline config as single string for ConfigMap data
CONFIG="artifactRepository:
  archiveLogs: true
  s3:
    bucket: ${BUCKET_NAME}
    endpoint: ${ENDPOINT}
    insecure: true
    accessKeySecret:
      name: ${SECRET_NAME}
      key: accesskey
    secretKeySecret:
      name: ${SECRET_NAME}
      key: secretkey
"

kubectl create configmap workflow-controller-configmap -n "${ARGO_NAMESPACE}" \
  --from-literal=config="${CONFIG}" \
  --dry-run=client -o yaml | kubectl apply -f -

kubectl rollout restart deployment workflow-controller -n "${ARGO_NAMESPACE}"
kubectl rollout status deployment workflow-controller -n "${ARGO_NAMESPACE}" --timeout=60s

echo "✅ Argo Workflows artifact repository is now Garage."
