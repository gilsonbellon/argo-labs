#!/bin/bash
# Only configure Garage: layout, bucket, key, and K8s secret for Argo.
# Use this if you already installed Garage with Helm yourself.
# Requires: GARAGE_NAMESPACE, first Garage pod (e.g. garage-0).

set -e

GARAGE_NAMESPACE="${GARAGE_NAMESPACE:-garage}"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argo}"
BUCKET_NAME="${BUCKET_NAME:-argo-workflows}"
KEY_NAME="${KEY_NAME:-argo-garage-key}"
SECRET_NAME="${SECRET_NAME:-my-garage-cred}"
GARAGE_POD="${GARAGE_POD:-garage-0}"

echo "🔧 Setting up bucket and key on existing Garage deployment..."
echo "   Pod: ${GARAGE_POD} in ${GARAGE_NAMESPACE}"
echo ""

GARAGE_CMD="garage"
kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- which garage &>/dev/null || GARAGE_CMD="./garage"

NODE_ID=$(kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} status 2>/dev/null | awk '/^[a-f0-9]/{print $1; exit}' || true)
if [ -z "${NODE_ID}" ]; then
  NODE_ID=$(kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} status 2>/dev/null | grep -o '^[a-f0-9]*' | head -1)
fi
if [ -z "${NODE_ID}" ]; then
  echo "❌ Could not get node ID. Run: kubectl exec -it -n ${GARAGE_NAMESPACE} ${GARAGE_POD} -- ${GARAGE_CMD} status"
  exit 1
fi

kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} layout assign -z dc1 -c 1G "${NODE_ID}"
kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} layout apply --version 1
kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} bucket create "${BUCKET_NAME}" 2>/dev/null || true
KEY_OUTPUT=$(kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} key create "${KEY_NAME}" 2>/dev/null || true)
kubectl exec -n "${GARAGE_NAMESPACE}" "${GARAGE_POD}" -- ${GARAGE_CMD} bucket allow --read --write --owner "${BUCKET_NAME}" --key "${KEY_NAME}"

KEY_ACCESS=$(echo "${KEY_OUTPUT}" | awk '/Key ID:/{print $3}')
KEY_SECRET=$(echo "${KEY_OUTPUT}" | awk '/Secret key:/{print $3}')
if [ -z "${KEY_ACCESS}" ] || [ -z "${KEY_SECRET}" ]; then
  echo "⚠️  Could not parse key. Create secret manually:"
  echo "   kubectl create secret generic ${SECRET_NAME} -n ${ARGO_NAMESPACE} --from-literal=accesskey=<Key ID> --from-literal=secretkey=<Secret key>"
  exit 1
fi

kubectl create namespace "${ARGO_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
kubectl create secret generic "${SECRET_NAME}" -n "${ARGO_NAMESPACE}" \
  --from-literal=accesskey="${KEY_ACCESS}" \
  --from-literal=secretkey="${KEY_SECRET}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "✅ Bucket ${BUCKET_NAME} and key ${KEY_NAME} created. Secret ${SECRET_NAME} created in ${ARGO_NAMESPACE}."
echo "   Next: run ./configure-argo-for-garage.sh to point Argo at Garage."
