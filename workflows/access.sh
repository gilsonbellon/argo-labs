#!/bin/bash
# Get Argo Workflows token and port forward to UI (per official docs)

set -e

NAMESPACE="argo"
SA_NAME="argo-ui"
SECRET_NAME="${SA_NAME}.service-account-token"

echo "🔐 Getting Argo Workflows access token..."
echo ""

# Get token from secret (per official documentation)
if kubectl -n ${NAMESPACE} get secret ${SECRET_NAME} &>/dev/null; then
    echo "📋 Using token from service account secret (per official docs)..."
    TOKEN=$(kubectl -n ${NAMESPACE} get secret ${SECRET_NAME} -o=jsonpath='{.data.token}' | base64 --decode)
    
    if [ -n "$TOKEN" ]; then
        echo "✅ Token retrieved!"
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📋 Your Token (use with 'Bearer' prefix):"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "Bearer $TOKEN"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "💡 In the web UI login:"
        echo "   - Username: can be anything"
        echo "   - Password: paste the token above (including 'Bearer')"
        echo ""
        
        # Test token
        echo "🧪 Testing token..."
        sleep 2
        TEST_RESULT=$(curl -k -s -w "\n%{http_code}" -H "Authorization: Bearer $TOKEN" https://localhost:2746/api/v1/info 2>/dev/null | tail -1)
        if [ "$TEST_RESULT" == "200" ]; then
            echo "✅ Token works! (Got 200 OK)"
        elif [ "$TEST_RESULT" == "000" ] || [ -z "$TEST_RESULT" ]; then
            echo "ℹ️  Port-forward not running yet (will start below)"
        else
            echo "⚠️  Token test returned: $TEST_RESULT (may need port-forward running)"
        fi
        echo ""
    else
        echo "❌ Could not extract token from secret"
        exit 1
    fi
else
    echo "❌ Secret ${SECRET_NAME} not found"
    echo "   Run ./install.sh first to set up authentication"
    exit 1
fi

echo "🌐 Starting port forward..."
echo "   Access UI at: https://localhost:2746"
echo "   Press Ctrl+C to stop"
echo ""

kubectl -n ${NAMESPACE} port-forward svc/argo-server 2746:2746
