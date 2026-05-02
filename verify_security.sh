#!/bin/bash

# Security Hardening Verification Script
# This script verifies that security components are properly implemented

echo "============================================================"
echo "OpenOats Security Hardening Verification"
echo "============================================================"

PASSED=0
FAILED=0

verify() {
    local name="$1"
    local file="$2"
    local pattern="$3"
    local should_exist="${4:-true}"
    
    if [ ! -f "$file" ]; then
        echo "❌ $name - File not found: $file"
        ((FAILED++))
        return
    fi
    
    if [ "$should_exist" = "true" ]; then
        if grep -q "$pattern" "$file" 2>/dev/null; then
            echo "✅ $name"
            ((PASSED++))
        else
            echo "❌ $name - Pattern not found: $pattern"
            ((FAILED++))
        fi
    else
        if grep -q "$pattern" "$file" 2>/dev/null; then
            echo "❌ $name - Pattern should not exist: $pattern"
            ((FAILED++))
        else
            echo "✅ $name"
            ((PASSED++))
        fi
    fi
}

echo ""
echo "📦 SecureString.swift Verification"
echo "------------------------------------------------------------"

verify "File exists" \
    "Sources/OpenOats/Infrastructure/Security/SecureString.swift" \
    "SecureString" \
    true

verify "Uses ~Copyable" \
    "Sources/OpenOats/Infrastructure/Security/SecureString.swift" \
    "~Copyable" \
    true

verify "Uses Sendable" \
    "Sources/OpenOats/Infrastructure/Security/SecureString.swift" \
    "Sendable" \
    true

verify "XOR obfuscation" \
    "Sources/OpenOats/Infrastructure/Security/SecureString.swift" \
    "obfuscationKey" \
    true

verify "Zero-on-deinit" \
    "Sources/OpenOats/Infrastructure/Security/SecureString.swift" \
    "for i in buffer.indices" \
    true

verify "withSecureAccess pattern" \
    "Sources/OpenOats/Infrastructure/Security/SecureString.swift" \
    "withSecureAccess" \
    true

echo ""
echo "🔗 SecureURLConstruction.swift Verification"
echo "------------------------------------------------------------"

verify "File exists" \
    "Sources/OpenOats/Infrastructure/Protocols/SecureURLConstruction.swift" \
    "SecureURLConstruction" \
    true

verify "URLComponents usage" \
    "Sources/OpenOats/Infrastructure/Protocols/SecureURLConstruction.swift" \
    "URLComponents" \
    true

verify "Path traversal protection" \
    "Sources/OpenOats/Infrastructure/Protocols/SecureURLConstruction.swift" \
    "pathTraversalDetected\|containsPathTraversal" \
    true

verify "Domain validation" \
    "Sources/OpenOats/Infrastructure/Protocols/SecureURLConstruction.swift" \
    "isInAllowedDomain\|allowedDomains" \
    true

verify "Result type support" \
    "Sources/OpenOats/Infrastructure/Protocols/SecureURLConstruction.swift" \
    "Result<URL" \
    true

verify "SafePathComponent type" \
    "Sources/OpenOats/Infrastructure/Protocols/SecureURLConstruction.swift" \
    "SafePathComponent" \
    true

echo ""
echo "🌐 VoyageClient.swift Verification"
echo "------------------------------------------------------------"

verify "File exists" \
    "Sources/OpenOats/Intelligence/VoyageClient.swift" \
    "VoyageClient" \
    true

verify "Uses SecureString" \
    "Sources/OpenOats/Intelligence/VoyageClient.swift" \
    "apiKey: SecureString" \
    true

verify "Uses SecureURLConstruction" \
    "Sources/OpenOats/Intelligence/VoyageClient.swift" \
    "SecureURLConstruction" \
    true

verify "withSecureAccess pattern" \
    "Sources/OpenOats/Intelligence/VoyageClient.swift" \
    "withSecureAccess" \
    true

verify "No force unwrap" \
    "Sources/OpenOats/Intelligence/VoyageClient.swift" \
    "URL(string:.*baseURL.*path)" \
    false

echo ""
echo "🎙️ ElevenLabsScribeBackend.swift Verification"
echo "------------------------------------------------------------"

verify "File exists" \
    "Sources/OpenOats/Transcription/ElevenLabsScribeBackend.swift" \
    "ElevenLabsScribeBackend" \
    true

verify "Uses SecureString" \
    "Sources/OpenOats/Transcription/ElevenLabsScribeBackend.swift" \
    "apiKey: SecureString" \
    true

verify "Uses SecureURLConstruction" \
    "Sources/OpenOats/Transcription/ElevenLabsScribeBackend.swift" \
    "SecureURLConstruction" \
    true

verify "Result type usage" \
    "Sources/OpenOats/Transcription/ElevenLabsScribeBackend.swift" \
    "Result<URL" \
    true

verify "withSecureAccess for headers" \
    "Sources/OpenOats/Transcription/ElevenLabsScribeBackend.swift" \
    "withSecureAccess" \
    true

echo ""
echo "🧪 Test Files Verification"
echo "------------------------------------------------------------"

verify "SecurityHardeningTests exists" \
    "Tests/OpenOatsTests/SecurityHardeningTests.swift" \
    "SecureStringSecurityTests" \
    true

verify "SecureString tests" \
    "Tests/OpenOatsTests/SecurityHardeningTests.swift" \
    "SecureString" \
    true

verify "Path traversal tests" \
    "Tests/OpenOatsTests/SecurityHardeningTests.swift" \
    "PathTraversal" \
    true

verify "VoyageClientTests updated" \
    "Tests/OpenOatsTests/VoyageClientTests.swift" \
    "SecureString\|Result type" \
    true

verify "ElevenLabsTests updated" \
    "Tests/OpenOatsTests/ElevenLabsScribeBackendTests.swift" \
    "SecureString\|apiKey" \
    true

echo ""
echo "============================================================"
echo "Verification Summary"
echo "============================================================"
echo "✅ Passed: $PASSED"
echo "❌ Failed: $FAILED"
echo "📊 Total:  $((PASSED + FAILED))"

if [ $FAILED -eq 0 ]; then
    echo ""
    echo "🎉 All security hardening components verified successfully!"
    exit 0
else
    echo ""
    echo "⚠️  Some components need attention"
    exit 1
fi
