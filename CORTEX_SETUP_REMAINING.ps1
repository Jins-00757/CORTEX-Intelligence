# Cortex Intelligence - Day 1 Setup (Remaining Files)
# This PowerShell script creates the remaining Day 1 configuration files that couldn't be transferred via remote tools
# Run this in PowerShell on your machine in the E:\CORTEX-Intelligence folder

$projectRoot = "E:\CORTEX-Intelligence"

# Create directory structure
@(".vscode", ".github\workflows", "docs") | ForEach-Object {
    $dir = Join-Path $projectRoot $_
    if (!(Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

# .vscode/settings.json
$vsCodeSettings = @{
    "[javascript]" = @{
        "editor.defaultFormatter" = "esbenp.prettier-vscode"
        "editor.formatOnSave" = $true
    }
    "eslint.validate" = @("javascript", "lwc")
    "files.exclude" = @{
        "**/.sfdx" = $true
        "**/node_modules" = $true
    }
    "search.exclude" = @{
        "**/node_modules" = $true
        "**/.sfdx" = $true
    }
} | ConvertTo-Json

Set-Content -Path "$projectRoot\.vscode\settings.json" -Value $vsCodeSettings

# .github/CODEOWNERS
$codeOwners = "* @jinal`n"
Set-Content -Path "$projectRoot\.github\CODEOWNERS" -Value $codeOwners

# .github/pull_request_template.md
$prTemplate = @"
# Pull Request: Cortex Intelligence

## Description
Brief overview of changes made.

## Type of Change
- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to change)
- [ ] Documentation update

## Related Issues
Closes #(issue number)

## Changes Made
- Change 1
- Change 2
- Change 3

## Testing Done
- [ ] Unit tests written/updated
- [ ] Integration tests passed
- [ ] Apex tests: coverage > 85%
- [ ] LWC components: Jest tests passing
- [ ] Manual testing completed

## Apex Code Quality
- [ ] No SOQL injection vulnerabilities
- [ ] No hardcoded credentials
- [ ] Proper error handling implemented
- [ ] Governor limits considered
- [ ] Debug logs added for troubleshooting

## Security Checklist
- [ ] No sensitive data in logs
- [ ] Input validation implemented
- [ ] Proper exception handling
- [ ] Audit logging added (if applicable)

## Screenshots (if applicable)
<!-- Add screenshots for UI changes -->

## Deployment Notes
<!-- Any special deployment instructions or considerations -->

## Reviewer Notes
<!-- Additional context for reviewers -->
"@

Set-Content -Path "$projectRoot\.github\pull_request_template.md" -Value $prTemplate

# .github/workflows/run-tests.yml
$workflowYml = @"
name: Run Apex Tests

on:
  push:
    branches: [develop, main]
  pull_request:
    branches: [develop, main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install SFDX CLI
        run: npm install -g @salesforce/cli

      - name: Authenticate with Salesforce
        env:
          SALESFORCE_JWT_KEY: `${{ secrets.SALESFORCE_JWT_KEY }}
          SALESFORCE_CLIENT_ID: `${{ secrets.SALESFORCE_CLIENT_ID }}
          SALESFORCE_USERNAME: `${{ secrets.SALESFORCE_DEV_USERNAME }}
        run: |
          echo "`$SALESFORCE_JWT_KEY" > server.key
          sf org login jwt \
            --client-id `$SALESFORCE_CLIENT_ID \
            --jwt-key-file server.key \
            --username `$SALESFORCE_USERNAME \
            --alias devOrg

      - name: Run Apex Tests
        run: sf apex run test --coverage --wait 20 --result-format json

      - name: Upload Coverage
        uses: codecov/codecov-action@v3
        with:
          files: ./coverage/apex-coverage.json
"@

Set-Content -Path "$projectRoot\.github\workflows\run-tests.yml" -Value $workflowYml

Write-Host "✅ Day 1 setup complete! All configuration files created." -ForegroundColor Green
Write-Host "Next steps:"
Write-Host "1. Open terminal in $projectRoot"
Write-Host "2. Run: npm install"
Write-Host "3. Run: npm run setup"
Write-Host "4. This will authenticate your Salesforce dev org and set up git hooks"
