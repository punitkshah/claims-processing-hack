#!/bin/bash
# Complete end-to-end test of the Claims Processing API
# Tests both local and deployed versions

set -e

echo "╔══════════════════════════════════════════════════════════╗"
echo "║     Claims Processing API - End-to-End Test              ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Resolve repo root relative to this script so paths work from any CWD
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Test image path
TEST_IMAGE="$REPO_ROOT/challenge-0/data/statements/crash1_front.jpeg"

if [ ! -f "$TEST_IMAGE" ]; then
    echo "❌ Test image not found: $TEST_IMAGE"
    exit 1
fi

echo "📸 Test image: $TEST_IMAGE"
echo ""

# Function to test an API endpoint
test_api() {
    local API_URL=$1
    echo "🎯 Testing API at: $API_URL"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    # Test 1: Health check
    echo ""
    echo "1️⃣ Testing health endpoint..."
    HEALTH_RESPONSE=$(curl -s "$API_URL/health")
    
    if echo "$HEALTH_RESPONSE" | grep -q '"status"[[:space:]]*:[[:space:]]*"healthy"'; then
        echo "   ✅ Health check passed"
        echo "   Response: $(echo "$HEALTH_RESPONSE" | head -c 100)..."
    else
        echo "   ❌ Health check failed"
        echo "   Response: $HEALTH_RESPONSE"
        return 1
    fi
    
    # Test 2: Process claim
    echo ""
    echo "2️⃣ Testing claim processing (file upload)..."
    echo "   Uploading image..."
    
    CLAIM_RESPONSE=$(curl -s -X POST "$API_URL/process-claim/upload" \
        -F "file=@$TEST_IMAGE" \
        -w "\n%{http_code}")
    
    HTTP_CODE=$(echo "$CLAIM_RESPONSE" | tail -n 1)
    RESPONSE_BODY=$(echo "$CLAIM_RESPONSE" | head -n -1)
    
    if [ "$HTTP_CODE" = "200" ]; then
        if echo "$RESPONSE_BODY" | grep -q '"success"[[:space:]]*:[[:space:]]*true'; then
            echo "   ✅ Claim processing succeeded"
            
            # Extract key information
            OCR_CHARS=$(echo "$RESPONSE_BODY" | grep -o '"ocr_characters"[[:space:]]*:[[:space:]]*[0-9]*' | head -1 | grep -o '[0-9]*$' || true)
            [ -z "$OCR_CHARS" ] && OCR_CHARS="unknown"
            echo "   📊 OCR characters extracted: $OCR_CHARS"
            
            # Check for vehicle info
            if echo "$RESPONSE_BODY" | grep -q '"vehicle_info"'; then
                echo "   🚗 Vehicle info detected"
            fi
            
            # Save full response (pretty-print via python if available, else raw)
            TIMESTAMP=$(date +%Y%m%d_%H%M%S)
            OUTPUT_FILE="test_result_${TIMESTAMP}.json"
            if command -v python3 >/dev/null 2>&1; then
                echo "$RESPONSE_BODY" | python3 -m json.tool > "$OUTPUT_FILE" 2>/dev/null || echo "$RESPONSE_BODY" > "$OUTPUT_FILE"
            else
                echo "$RESPONSE_BODY" > "$OUTPUT_FILE"
            fi
            echo "   💾 Full response saved to: $OUTPUT_FILE"
            
        else
            echo "   ❌ Claim processing failed"
            ERROR=$(echo "$RESPONSE_BODY" | grep -o '"error"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"\([^"]*\)"$/\1/' || true)
            [ -z "$ERROR" ] && ERROR="unknown"
            echo "   Error: $ERROR"
            return 1
        fi
    else
        echo "   ❌ HTTP error: $HTTP_CODE"
        echo "   Response: $RESPONSE_BODY"
        return 1
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "✅ All tests passed for $API_URL"
    echo ""
    
    return 0
}

# Main test logic
if [ $# -eq 0 ]; then
    # Test local server
    echo "🏠 Testing LOCAL server (http://localhost:8080)"
    echo ""
    
    # Check if server is running
    if ! curl -s http://localhost:8080/health > /dev/null 2>&1; then
        echo "❌ Local server not running at http://localhost:8080"
        echo ""
        echo "To start the server, run:"
        echo "  python api_server.py"
        echo ""
        exit 1
    fi
    
    test_api "http://localhost:8080"
    
else
    # Test provided URL
    API_URL=$1
    # Remove trailing slash
    API_URL=${API_URL%/}
    
    echo "☁️  Testing DEPLOYED server ($API_URL)"
    echo ""
    
    test_api "$API_URL"
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║              ✅ END-TO-END TEST COMPLETE ✅              ║"
echo "╚══════════════════════════════════════════════════════════╝"
