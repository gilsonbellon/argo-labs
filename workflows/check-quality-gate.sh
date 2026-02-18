#!/bin/bash
# Check SonarQube quality gate status (simpler version)

set -e

PROJECT_KEY="${1:-test-project}"
SONARQUBE_NAMESPACE="sonarqube"
ARGO_NAMESPACE="${ARGO_NAMESPACE:-argo}"

echo "🔍 Checking Quality Gate for: ${PROJECT_KEY}"
echo ""

# Get token from secret
if ! kubectl get secret sonarqube-credentials -n ${ARGO_NAMESPACE} >/dev/null 2>&1; then
  echo "❌ SonarQube credentials secret not found!"
  exit 1
fi

TOKEN=$(kubectl get secret sonarqube-credentials -n ${ARGO_NAMESPACE} -o jsonpath='{.data.token}' | base64 -d)

# Check quality gate
kubectl run -it --rm --restart=Never check-qg-$(date +%s) \
  --image=curlimages/curl -n ${ARGO_NAMESPACE} -- \
  sh -c "
    RESPONSE=\$(curl -s -u \"${TOKEN}:\" \
      \"http://sonarqube.${SONARQUBE_NAMESPACE}.svc:9000/api/qualitygates/project_status?projectKey=${PROJECT_KEY}\")
    
    STATUS=\$(echo \"\$RESPONSE\" | grep -o '\"status\":\"[^\"]*\"' | cut -d'\"' -f4)
    
    if [ \"\$STATUS\" = \"OK\" ]; then
      echo \"✅ Quality Gate: PASSED\"
    elif [ \"\$STATUS\" = \"ERROR\" ]; then
      echo \"❌ Quality Gate: FAILED\"
      echo \"\"
      echo \"Details:\"
      echo \"\$RESPONSE\" | grep -o '\"conditions\":\[[^\]]*\]' || echo \"\$RESPONSE\"
    else
      echo \"⚠️  Quality Gate Status: \$STATUS\"
      echo \"\"
      echo \"Full response:\"
      echo \"\$RESPONSE\"
    fi
  " 2>/dev/null || {
    echo "❌ Failed to check quality gate"
    echo "   Make sure the project exists and has been scanned"
    exit 1
  }
