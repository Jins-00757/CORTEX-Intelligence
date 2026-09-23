@echo off
REM Cortex Intelligence - Day 1 Setup (Remaining Files)
REM This batch script creates the remaining Day 1 configuration files
REM Run this in Command Prompt in the E:\CORTEX-Intelligence folder

setlocal enabledelayedexpansion

set projectRoot=E:\CORTEX-Intelligence

echo Creating directory structure...
if not exist "%projectRoot%\.vscode" mkdir "%projectRoot%\.vscode"
if not exist "%projectRoot%\.github\workflows" mkdir "%projectRoot%\.github\workflows"

echo Creating .vscode/settings.json...
(
echo {
echo   "[javascript]": {
echo     "editor.defaultFormatter": "esbenp.prettier-vscode",
echo     "editor.formatOnSave": true
echo   },
echo   "eslint.validate": ["javascript", "lwc"],
echo   "files.exclude": {
echo     "**/.sfdx": true,
echo     "**/node_modules": true
echo   },
echo   "search.exclude": {
echo     "**/node_modules": true,
echo     "**/.sfdx": true
echo   }
echo }
) > "%projectRoot%\.vscode\settings.json"

echo Creating .github/CODEOWNERS...
(
echo * @jinal
) > "%projectRoot%\.github\CODEOWNERS"

echo Creating .github/pull_request_template.md...
(
echo # Pull Request: Cortex Intelligence
echo.
echo ## Description
echo Brief overview of changes made.
echo.
echo ## Type of Change
echo - [ ] Bug fix ^(non-breaking change that fixes an issue^)
echo - [ ] New feature ^(non-breaking change that adds functionality^)
echo - [ ] Breaking change ^(fix or feature that would cause existing functionality to change^)
echo - [ ] Documentation update
echo.
echo ## Related Issues
echo Closes #^(issue number^)
echo.
echo ## Changes Made
echo - Change 1
echo - Change 2
echo - Change 3
echo.
echo ## Testing Done
echo - [ ] Unit tests written/updated
echo - [ ] Integration tests passed
echo - [ ] Apex tests: coverage ^> 85%%
echo - [ ] LWC components: Jest tests passing
echo - [ ] Manual testing completed
echo.
echo ## Apex Code Quality
echo - [ ] No SOQL injection vulnerabilities
echo - [ ] No hardcoded credentials
echo - [ ] Proper error handling implemented
echo - [ ] Governor limits considered
echo - [ ] Debug logs added for troubleshooting
echo.
echo ## Security Checklist
echo - [ ] No sensitive data in logs
echo - [ ] Input validation implemented
echo - [ ] Proper exception handling
echo - [ ] Audit logging added ^(if applicable^)
echo.
echo ## Screenshots ^(if applicable^)
echo.
echo ## Deployment Notes
echo.
echo ## Reviewer Notes
) > "%projectRoot%\.github\pull_request_template.md"

echo Creating .github/workflows/run-tests.yml...
(
echo name: Run Apex Tests
echo.
echo on:
echo   push:
echo     branches: [develop, main]
echo   pull_request:
echo     branches: [develop, main]
echo.
echo jobs:
echo   test:
echo     runs-on: ubuntu-latest
echo     steps:
echo       - uses: actions/checkout@v4
echo.
echo       - name: Install SFDX CLI
echo         run: npm install -g @salesforce/cli
echo.
echo       - name: Authenticate with Salesforce
echo         env:
echo           SALESFORCE_JWT_KEY: ${{ secrets.SALESFORCE_JWT_KEY }}
echo           SALESFORCE_CLIENT_ID: ${{ secrets.SALESFORCE_CLIENT_ID }}
echo           SALESFORCE_USERNAME: ${{ secrets.SALESFORCE_DEV_USERNAME }}
echo         run: ^|
echo           echo "$SALESFORCE_JWT_KEY" ^> server.key
echo           sf org login jwt \
echo             --client-id $SALESFORCE_CLIENT_ID \
echo             --jwt-key-file server.key \
echo             --username $SALESFORCE_USERNAME \
echo             --alias devOrg
echo.
echo       - name: Run Apex Tests
echo         run: sf apex run test --coverage --wait 20 --result-format json
echo.
echo       - name: Upload Coverage
echo         uses: codecov/codecov-action@v3
echo         with:
echo           files: ./coverage/apex-coverage.json
) > "%projectRoot%\.github\workflows\run-tests.yml"

echo.
echo ===================================
echo ✅ All configuration files created!
echo ===================================
echo.
echo Next steps:
echo 1. Open terminal/PowerShell in: %projectRoot%
echo 2. Run: npm install
echo 3. Run: npm run setup
echo.
pause
