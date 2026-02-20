#!/bin/bash
# Deploy Garage on Kubernetes and set it up for Argo Workflows:
# - Clone Garage repo (or use GARAGE_HELM_PATH)
# - Helm install Garage
# - Configure layout, create bucket argo-workflows and key argo-garage-key
# - Create secret my-garage-cred in namespace argo
# You still need to run configure-argo-for-garage.sh to point Argo at Garage.

set -e

GARAGE_NAMESPACE="${GARAGE_NAMESPACE:-garage}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argo}"
BUCKET_NAME="${BUCKET_NAME:-argo-workflows}"
KEY_NAME="${KEY_NAME:-argo-garage-key}"
SECRET_NAME="${SECRET_NAME:-my-garage-cred}"
# If set, use this path instead of cloning (e.g. /path/to/garage/script/helm)
GARAGE_HELM_PATH="${GARAGE_HELM_PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALUES_FILE="${SCRIPT_DIR}/values-override.yaml"

echo "📦 Garage deployment for Argo Workflows"
echo "   Namespace: ${GARAGE_NAMESPACE}"
echo "   Argo namespace: ${ARGO_NAMESPACE}"
echo "   Bucket: ${BUCKET_NAME}"
echo "   Key: ${KEY_NAME}"
echo ""

# Resolve Helm chart path
if [ -n "${GARAGE_HELM_PATH}" ]; then
  HELM_CHART_DIR="${GARAGE_HELM_PATH}"
  echo "Using existing Garage Helm path: ${HELM_CHART_DIR}"
else
  TMP_GARAGE="${SCRIPT_DIR}/.garage-clone"
  if [ ! -d "${TMP_GARAGE}/script/helm/garage" ]; then
    echo "Cloning Garage repository..."
    git clone --depth 1 https://git.deuxfleurs.fr/Deuxfleurs/garage "${TMP_GARAGE}"
  else
    echo "Using existing clone at ${TMP_GARAGE}"
  fi
  HELM_CHART_DIR="${TMP_GARAGE}/script/helm"
fi

# Install or upgrade
echo "Installing Garage with Helm..."
if [ -f "${VALUES_FILE}" ]; then
  helm upgrade --install garage "${HELM_CHART_DIR}/garage" \
    --create-namespace \
    --namespace "${GARAGE_NAMESPACE}" \
    -f "${VALUES_FILE}"
else
  helm upgrade --install garage "${HELM_CHART_DIR}/garage" \
    --create-namespace \
    --namespace "${GARAGE_NAMESPACE}"
fi

echo "⏳ Waiting for Garage pod(s)..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=garage -n "${GARAGE_NAMESPACE}" --timeout=120s || true
# Fallback label
kubectl wait --for=condition=ready pod -l app=garage -n "${GARAGE_NAMESPACE}" --timeout=120s 2>/dev/null || true
GARAGE_POD=$(kubectl get pods -n "${GARAGE_NAMESPACE}" -o name | head -1)
if [ -z "${GARAGE_POD}" ]; then
  GARAGE_POD="garage-0"
fi
GARAGE_POD="${GARAGE_POD#pod/}"

echo "🔧 Fixing replication factor in configmap..."
# Helm chart may set replication_factor = 3 even if replicationMode: "1" in values
# Check and fix the configmap if needed
REPLICATION_MODE=$(grep -E "^\s*replicationMode:" "${VALUES_FILE}" 2>/dev/null | awk '{print $2}' | tr -d '"' || echo "1")
if [ -n "${REPLICATION_MODE}" ]; then
  CURRENT_REPLICATION=$(kubectl get configmap garage-config -n "${GARAGE_NAMESPACE}" -o jsonpath='{.data.garage\.toml}' 2>/dev/null | grep -E "^\s*replication_factor\s*=" | awk '{print $3}' || echo "")
  if [ "${CURRENT_REPLICATION}" != "${REPLICATION_MODE}" ]; then
    echo "   Updating replication_factor from ${CURRENT_REPLICATION} to ${REPLICATION_MODE}..."
    kubectl get configmap garage-config -n "${GARAGE_NAMESPACE}" -o yaml | \
      sed "s/replication_factor = ${CURRENT_REPLICATION}/replication_factor = ${REPLICATION_MODE}/" | \
      kubectl apply -f - 2>/dev/null || true
    
    # Restart pod to pick up new config
    echo "   Restarting Garage pod to apply new config..."
    kubectl delete pod "${GARAGE_POD}" -n "${GARAGE_NAMESPACE}" 2>/dev/null || true
    kubectl wait --for=condition=ready pod "${GARAGE_POD}" -n "${GARAGE_NAMESPACE}" --timeout=120s || true
  fi
fi

echo "🔧 Configuring layout and bucket..."
# Get node ID
GARAGE_CMD="./garage"
# Try to find garage binary
if ! kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} status &>/dev/null; then
  GARAGE_CMD="garage"
fi

# Wait a bit for Garage to be fully ready
sleep 5

NODE_ID=$(kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} status 2>/dev/null | awk '/^[a-f0-9]/{print $1; exit}' || true)
if [ -z "${NODE_ID}" ]; then
  NODE_ID=$(kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} status 2>/dev/null | grep -o '^[a-f0-9]*' | head -1 || true)
fi
if [ -z "${NODE_ID}" ]; then
  echo "⚠️  Could not get Garage node ID. Run manually:"
  echo "   kubectl exec -it -n ${GARAGE_NAMESPACE} ${GARAGE_POD} -- ${GARAGE_CMD} status"
  echo "   Then: garage layout assign -z dc1 -c 1G <NODE_ID>"
  echo "   Then: garage layout apply --version 1"
  exit 1
fi

# Assign layout
kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} layout assign -z dc1 -c 1G "${NODE_ID}" || true

# Apply layout (may fail if replication factor mismatch - handled below)
LAYOUT_APPLY_OUTPUT=$(kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} layout apply --version 1 2>&1 || true)
if echo "${LAYOUT_APPLY_OUTPUT}" | grep -q "replication factor"; then
  echo "⚠️  Layout apply failed due to replication factor mismatch."
  echo "   This usually means the configmap wasn't updated. Checking..."
  # Double-check configmap
  kubectl get configmap garage-config -n "${GARAGE_NAMESPACE}" -o jsonpath='{.data.garage\.toml}' | grep replication_factor
  echo "   If replication_factor is not ${REPLICATION_MODE}, you may need to delete metadata PVC:"
  echo "   kubectl delete pvc meta-${GARAGE_POD} -n ${GARAGE_NAMESPACE}"
  echo "   kubectl delete pod ${GARAGE_POD} -n ${GARAGE_NAMESPACE}"
  exit 1
fi

# Verify layout is applied before creating bucket/key
LAYOUT_STATUS=$(kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} status 2>/dev/null || true)
if echo "${LAYOUT_STATUS}" | grep -q "pending..."; then
  echo "⚠️  Layout not applied yet. Waiting a moment and retrying..."
  sleep 3
  kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} layout apply --version 1 || true
fi

kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} bucket create "${BUCKET_NAME}" 2>/dev/null || true
KEY_OUTPUT=$(kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} key create "${KEY_NAME}" 2>/dev/null || true)
kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} bucket allow --read --write --owner "${BUCKET_NAME}" --key "${KEY_NAME}"

# Parse Key ID and Secret key (handle both table format and simple format)
KEY_ACCESS=$(echo "${KEY_OUTPUT}" | grep -E "Key ID:" | awk '{print $3}' | head -1)
KEY_SECRET=$(echo "${KEY_OUTPUT}" | grep -E "Secret key:" | awk '{print $3}' | head -1)
if [ -z "${KEY_ACCESS}" ] || [ -z "${KEY_SECRET}" ]; then
  echo "⚠️  Could not parse key from garage key create. Create secret manually:"
  echo "   kubectl create secret generic ${SECRET_NAME} -n ${ARGO_NAMESPACE} --from-literal=accesskey=<Key ID> --from-literal=secretkey=<Secret key>"
  exit 1
fi

# Ensure argo namespace exists
kubectl create namespace "${ARGO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -

kubectl create secret generic "${SECRET_NAME}" -n "${ARGO_NAMESPACE}" \
  --from-literal=accesskey="${KEY_ACCESS}" \
  --from-literal=secretkey="${KEY_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "✅ Garage is installed and configured."
echo "   Next: run ./configure-argo-for-garage.sh to point Argo at Garage."
