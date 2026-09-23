#!/bin/bash

# Development environment setup script

set -e

echo "🚀 Setting up Cortex Intelligence Development Environment"
echo "=========================================================="

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Check Node.js
echo "Checking Node.js installation..."
if ! command -v node &> /dev/null; then
    echo "Node.js is required. Please install from https://nodejs.org/"
    exit 1
fi
echo -e "${GREEN}✓ Node.js $(node -v)${NC}"

# Check npm
echo "Checking npm installation..."
if ! command -v npm &> /dev/null; then
    echo "npm is required."
    exit 1
fi
echo -e "${GREEN}✓ npm $(npm -v)${NC}"

# Check Salesforce CLI
echo "Checking Salesforce CLI..."
if ! command -v sf &> /dev/null; then
    echo -e "${YELLOW}Installing Salesforce CLI...${NC}"
    npm install -g @salesforce/cli
fi
echo -e "${GREEN}✓ Salesforce CLI${NC}"

# Install npm dependencies (skip if already installed)
if [ -d node_modules ]; then
    echo -e "${GREEN}✓ node_modules already present, skipping npm install${NC}"
else
    echo -e "${YELLOW}Installing npm dependencies...${NC}"
    npm install
fi

# Setup Salesforce org connection (skip if a default connected org already exists)
if sf org list --json 2>/dev/null | grep -q '"isDefaultUsername": true'; then
    echo -e "${GREEN}✓ Default Salesforce org already connected, skipping login${NC}"
else
    echo -e "${YELLOW}Setting up Salesforce org connection...${NC}"
    echo "Please login to your Developer Edition org:"
    sf org login web --alias cortex-dev
    sf config set target-org=cortex-dev
fi

# Verify connection
echo "Verifying connection..."
sf org list

# Create force-app directory structure
echo -e "${YELLOW}Creating force-app directory structure...${NC}"
mkdir -p force-app/main/default/{classes,lwc,triggers,objects,flows,platformEvents,customMetadata,staticresources}

# Initialize git repository if missing (husky requires a git repo)
if [ ! -d .git ]; then
    echo -e "${YELLOW}Initializing git repository...${NC}"
    git init
fi

# Setup git hooks
echo -e "${YELLOW}Setting up git hooks...${NC}"
npx husky install 2>/dev/null || true
npx husky add .husky/pre-commit "npx lint-staged" 2>/dev/null || true

echo -e "${GREEN}✅ Development environment setup complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Review documentation: docs/*.md"
echo "2. Deploy metadata: npm run deploy"
echo "3. Run tests: npm test"
echo "4. Start developing!"
