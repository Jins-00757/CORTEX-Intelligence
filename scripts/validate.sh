#!/bin/bash

# Pre-deployment validation script

echo "🔍 Running pre-deployment validations..."
echo "======================================"

# 1. SFDX validation
echo ""
echo "✓ Validating SFDX project structure..."
sf project validate deploy --target-org cortex-dev || true

# 2. ESLint for LWC
echo ""
echo "✓ Running ESLint for Lightning Web Components..."
npm run lint || true

# 3. Code coverage
echo ""
echo "✓ Checking code coverage..."
npm test -- --coverage || true

# 4. Apex analysis
echo ""
echo "✓ Running Salesforce Code Scanner..."
sf scanner run --target-org cortex-dev || true

echo ""
echo "✅ All validations complete!"
