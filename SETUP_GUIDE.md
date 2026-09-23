# Cortex Intelligence - Complete Setup Guide

**Date:** September 22, 2026  
**Status:** Ready for Configuration

---

## ✅ What's Complete

All 14 Day 1 foundation files are now in your `E:\CORTEX-Intelligence` folder. You're ready to complete the setup process.

---

## 📋 Setup Checklist

### Step 1: Create Remaining Configuration Files

**Choose ONE method:**

#### Option A: Run Batch Script (Easiest)

1. Open Command Prompt or PowerShell
2. Navigate to your project folder:
   ```cmd
   cd E:\CORTEX-Intelligence
   ```
3. Run the batch script:
   ```cmd
   CORTEX_SETUP_REMAINING.bat
   ```
   This will automatically create:
   - `.vscode/settings.json`
   - `.github/CODEOWNERS`
   - `.github/pull_request_template.md`
   - `.github/workflows/run-tests.yml`

#### Option B: Manual File Creation

If the batch script doesn't work, create these 4 files manually:

**File 1: `.vscode/settings.json`**
```json
{
  "[javascript]": {
    "editor.defaultFormatter": "esbenp.prettier-vscode",
    "editor.formatOnSave": true
  },
  "eslint.validate": ["javascript", "lwc"],
  "files.exclude": {
    "**/.sfdx": true,
    "**/node_modules": true
  },
  "search.exclude": {
    "**/node_modules": true,
    "**/.sfdx": true
  }
}
```

**File 2: `.github/CODEOWNERS`**
```
* @jinal
```

**File 3: `.github/pull_request_template.md`**
(Copy from DAY_1_COMPLETION_SUMMARY.md or README.md)

**File 4: `.github/workflows/run-tests.yml`**
(Copy from README.md or DEPLOYMENT.md)

---

### Step 2: Install npm Dependencies

1. Open Terminal/PowerShell in your project folder:
   ```bash
   cd E:\CORTEX-Intelligence
   ```

2. Install all dependencies:
   ```bash
   npm install
   ```

   **Expected Output:**
   ```
   npm notice created a lockfile as package-lock.json
   added X packages, and audited Y packages in Zs
   ```

   **This installs:**
   - `@salesforce/cli` - SFDX CLI for Salesforce operations
   - ESLint - Code quality checker
   - Jest - JavaScript testing framework
   - Prettier - Code formatter
   - Husky - Git hooks
   - And other development dependencies

   ⏱️ **Time:** 2-3 minutes

---

### Step 3: Run Dev Environment Setup

1. In the same terminal, run:
   ```bash
   npm run setup
   ```

2. **What this script does:**
   - ✅ Verifies Node.js version (v20+)
   - ✅ Verifies npm is installed
   - ✅ Verifies Salesforce CLI is installed
   - ✅ Creates `force-app/main/default/` directory structure
   - ✅ Sets up git pre-commit hooks (ESLint + Prettier)

3. **Next prompts:**
   
   The script will ask you to authenticate with Salesforce:
   ```
   ? Enter your Salesforce org username: [your-salesforce-email@example.com]
   ```

   Provide your Salesforce Developer Edition org username.

4. **After authentication:**
   ```
   ✅ Git hooks configured successfully
   ✅ Dev environment setup complete!
   ```

   ⏱️ **Time:** 1-2 minutes

---

## 🔐 Salesforce Dev Org Setup

If you don't have a Salesforce Developer Edition org yet:

1. Visit: https://developer.salesforce.com/signup
2. Sign up for a free Developer Edition org
3. Verify your email
4. Set your username (you'll need this during `npm run setup`)
5. Create a password

**Note:** The setup script will open a browser window for OAuth authentication. Click "Allow" when prompted.

---

## ✅ Verification Checklist

After setup is complete, verify everything:

```bash
# Check all files exist
ls -la E:\CORTEX-Intelligence

# Verify folder structure
tree /L 2 E:\CORTEX-Intelligence

# Run linter (should have no errors)
npm run lint

# Verify tests can run (sample test)
npm run test

# Validate SFDX project
npm run validate
```

**Expected results:**
- ✅ `node_modules/` folder created (200+ MB)
- ✅ `force-app/main/default/` folder structure exists
- ✅ `.git/` folder present
- ✅ ESLint validation passes
- ✅ Jest finds test files
- ✅ SFDX validates without errors

---

## 📁 Your Project Structure Now

After setup, your folder will look like:

```
E:\CORTEX-Intelligence/
├── .git/                          # Git repository
├── .github/
│   ├── CODEOWNERS                # Code ownership
│   ├── pull_request_template.md  # PR standards
│   └── workflows/
│       └── run-tests.yml         # CI/CD pipeline
├── .vscode/
│   └── settings.json             # VS Code config
├── .gitignore                    # Git exclusions
├── .eslintrc.json                # ESLint config
├── .lintstagedrc.json            # Pre-commit hooks
├── jest.config.js                # Jest config
├── package.json                  # npm config + 13 scripts
├── package-lock.json             # Dependency lock file
├── sfdx-project.json             # SFDX config
├── README.md                     # Project overview
├── DAY_1_COMPLETION_SUMMARY.md   # Day 1 summary
├── CORTEX_SETUP_REMAINING.bat    # Setup script
├── node_modules/                 # Installed packages (200+ MB)
├── force-app/
│   └── main/default/             # Salesforce source code
│       ├── classes/              # Apex classes (empty - Day 2)
│       ├── lwc/                  # LWC components (empty - Day 5)
│       ├── objects/              # Custom objects (empty - Day 2)
│       ├── triggers/             # Apex triggers (empty - Day 3)
│       ├── flows/                # Automated flows (empty - Day 7)
│       ├── platformEvents/       # Events (empty - Day 2)
│       ├── customMetadata/       # Config (empty - Day 2)
│       └── staticresources/      # Assets (empty)
├── scripts/
│   ├── setup-dev.sh              # Setup automation
│   └── validate.sh               # Deployment validation
└── docs/
    ├── ARCHITECTURE.md           # System design
    └── DEPLOYMENT.md             # Deployment guide
```

---

## 🔧 Troubleshooting

### Issue: "npm not found" or "node not found"

**Solution:**
- Verify Node.js v20+ is installed: `node --version`
- Verify npm is installed: `npm --version`
- If not installed, download from: https://nodejs.org/ (LTS version)
- Restart your terminal after installing

### Issue: "Salesforce CLI not found"

**Solution:**
- Install SFDX CLI: `npm install -g @salesforce/cli`
- Verify: `sf --version`

### Issue: Authentication fails during `npm run setup`

**Solution:**
- Make sure you're using a Salesforce Developer Edition username (not email sometimes)
- Check that your org is active (not expired)
- You can re-authenticate with: `sf org login web --alias dev-org`

### Issue: Port conflicts or git errors

**Solution:**
- Delete `node_modules/` and `package-lock.json`
- Run: `npm install` again
- Run: `npm run setup` again

---

## 🚀 What's Next After Setup?

Once setup is complete:

1. **Verify connectivity:**
   ```bash
   sf org list
   ```
   You should see your dev org listed.

2. **Begin Day 2 (Data Model):**
   - Create BigObjects for massive-scale data
   - Create Custom Objects for master data
   - Define Platform Events for real-time streaming
   - See `CORTEX_10DAY_DEPLOYMENT_PLAN.md` for details

3. **Daily development workflow:**
   ```bash
   # Write code
   npm run lint          # Check code quality
   npm run format        # Auto-format code
   npm test              # Run tests
   npm run deploy        # Deploy to dev org
   npm run retrieve      # Get latest from org
   ```

---

## 💡 Key npm Scripts

| Script | Purpose |
|--------|---------|
| `npm run dev` | Open dev org in browser |
| `npm test` | Run all tests with coverage |
| `npm run test:apex` | Run Apex tests only |
| `npm run lint` | Check code quality |
| `npm run format` | Auto-format all code |
| `npm run validate` | Pre-deployment validation |
| `npm run deploy` | Deploy to dev org |
| `npm run deploy:test` | Deploy with full tests |
| `npm run retrieve` | Fetch latest from org |
| `npm run scan` | Security code scan |
| `npm run setup` | (Already run) Dev setup |

---

## 📞 Support

- **Architecture:** See `docs/ARCHITECTURE.md`
- **Deployment:** See `docs/DEPLOYMENT.md`
- **10-Day Plan:** See `CORTEX_10DAY_DEPLOYMENT_PLAN.md`
- **Issues:** Review the troubleshooting section above

---

## ✅ You're Ready!

**Summary of what you now have:**
- ✅ Complete Day 1 foundation files in `E:\CORTEX-Intelligence`
- ✅ SFDX project configuration (Salesforce Winter 2027, API v61.0)
- ✅ npm scripts for build, test, deploy, validate
- ✅ ESLint + Prettier for code quality
- ✅ Jest testing framework (85%+ coverage target)
- ✅ GitHub Actions CI/CD pipeline
- ✅ Complete architecture & deployment documentation
- ✅ Ready to authenticate your Salesforce dev org

**Estimated time to complete setup:** 5-10 minutes (mostly waiting for `npm install`)

---

**Version:** 1.0  
**Next:** Day 2 - Data Model Design  
**Questions?** Review docs or contact: jinalraval2022@gmail.com
