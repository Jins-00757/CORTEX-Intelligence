# Cortex Intelligence - Deployment Guide

**Version:** 1.0  
**Date:** September 22, 2026  
**Audience:** DevOps, Salesforce Admins, Technical Leads

---

## Pre-Deployment Checklist

**Before deploying to any environment:**

- [ ] All unit tests passing (Apex 95%+, LWC 85%+)
- [ ] Code coverage acceptable (minimum 85%)
- [ ] Security scan complete (no critical vulnerabilities)
- [ ] Performance tested (API < 500ms, Dashboard < 2s)
- [ ] Peer code review completed and approved
- [ ] Deployment plan documented
- [ ] Rollback procedure tested
- [ ] Stakeholders notified

---

## Deployment Environments

### 1. Development Environment

**Org Type:** Developer Edition  
**Purpose:** Feature development and testing  
**Access:** All developers

```bash
# Deploy to dev org
npm run deploy

# With tests
npm run deploy:test

# Retrieve latest metadata
npm run retrieve
```

### 2. Staging Environment

**Org Type:** Sandbox (Full Copy or Developer)  
**Purpose:** Pre-production testing, UAT  
**Access:** QA, Product Managers

```bash
# Authenticate with staging
sf org login web --alias staging-org

# Validate deployment first
sf project validate deploy --target-org staging-org --test-level RunAllLocalTests

# Execute deployment
sf project deploy start --target-org staging-org --test-level RunAllLocalTests --wait 30
```

### 3. Production Environment

**Org Type:** Production Org  
**Purpose:** Live system serving customers  
**Access:** Controlled by change management

**Deployment Windows:**
- Preferred: 2-4 AM UTC (low-traffic hours)
- Blackout Periods: Major holidays, quarter-end close

---

## Deployment Process

### Step 1: Pre-Deployment Validation

```bash
# Ensure all code committed
git status

# Run local tests
npm test
npm run test:apex

# Validate in target org (no changes applied)
sf project validate deploy \
  --target-org production \
  --test-level RunAllLocalTests \
  --wait 30
```

### Step 2: Create Deployment Plan

**Document:**
- Changes being deployed
- Risk assessment (low/medium/high)
- Rollback procedure
- Estimated deployment time
- Success criteria

### Step 3: Secure Approvals

**For Production:**
1. Code owner review (approved)
2. QA sign-off
3. Change management approval
4. Business stakeholder notification

### Step 4: Execute Deployment

```bash
# For production, use scheduled deployment
# to control exact deployment time
sf project deploy start \
  --target-org production \
  --test-level RunAllLocalTests \
  --wait 60 \
  --verbose
```

**Monitor:**
- Deployment status in Salesforce Setup
- Deployment logs for errors
- Error rate monitoring

### Step 5: Post-Deployment Verification

```bash
# Check deployment status
sf project deploy report --target-org production

# Verify key functionality:
# 1. Navigate to Cortex dashboard
# 2. Test API endpoints
# 3. Run batch jobs
# 4. Check error logs

echo "Post-deployment verification checklist:
- [ ] Dashboard loads (< 2s)
- [ ] API endpoints responding
- [ ] Batch predictions running
- [ ] No spike in error logs
- [ ] Performance metrics acceptable
"
```

---

## Rollback Procedure

**If deployment fails or critical issues arise:**

### Automatic Rollback
Salesforce automatically rolls back if:
- Tests fail
- Deployment errors occur
- Validation fails

### Manual Rollback

```bash
# 1. Identify previous stable version
git log --oneline -10

# 2. Revert to previous commit
git revert HEAD

# 3. Validate in production
sf project validate deploy \
  --target-org production \
  --test-level RunAllLocalTests

# 4. Deploy previous version
sf project deploy start \
  --target-org production \
  --test-level RunAllLocalTests

# 5. Notify stakeholders
# Explain what went wrong and resolution
```

---

## Configuration Management

### Custom Metadata Configuration

**Post-deployment setup in target org:**

1. **Navigate to:** Setup → Custom Metadata Type Records → CortexConfig
2. **Configure Default Record:**
   ```
   Batch_Size__c = 10000
   Max_API_Calls_Per_Hour__c = 1000
   Churn_Risk_Threshold__c = 0.70
   Log_Level__c = INFO (DEBUG for dev)
   Data_Retention_Days__c = 730
   ```

3. **Feature Flags:**
   ```json
   {
     "churn_prediction": true,
     "lookalike_scoring": true,
     "rfm_analysis": true,
     "realtime_processing": true
   }
   ```

### Scheduled Jobs

**Schedule in target org:**

```apex
// In Salesforce Developer Console
String jobId = System.schedule(
    'Cortex Churn Prediction - Nightly',
    '0 2 * * *',  // 2 AM UTC daily
    new ChurnPredictionSchedulable()
);
System.debug('Scheduled Job ID: ' + jobId);
```

### OAuth Integration Setup

**For API external systems:**

1. Connected App created in Salesforce
2. OAuth 2.0 credentials generated
3. Credentials shared with integration team (securely)
4. Test API connectivity

---

## Performance Baseline

**Capture before going live:**

```bash
# Load test dashboard
# Document: Load time, response time distribution

# Test API endpoints at scale
# Document: Throughput, error rates, latency percentiles

# Monitor batch job duration
# Document: Full execution time, records processed

# Baseline query performance
# Document: Query times for common patterns
```

**Production SLAs:**
- API response time: < 500ms (95th percentile)
- Dashboard load time: < 2 seconds
- Batch job completion: < 1 hour
- Uptime: 99.5%

---

## Monitoring & Support

### Daily Monitoring

```bash
# Check error logs
# Setup → Monitor → Apex Debug Logs
# Filter for: ERROR, WARN levels

# Check batch job status
# Setup → Monitoring → Scheduled Jobs
# Verify nightly churn prediction completed

# Monitor API usage
# Setup → Integrations → API Usage
# Check for spikes or errors
```

### Key Metrics to Monitor

| Metric | Acceptable | Alert Threshold |
|--------|-----------|-----------------|
| API Error Rate | < 0.1% | > 1% |
| Dashboard Load Time | < 2s | > 5s |
| Batch Job Duration | < 1h | > 1.5h |
| Database Query Time | < 100ms | > 500ms |

### Troubleshooting Deployment Issues

**Issue:** "INVALID_DEPLOYMENT" error

**Solution:**
```bash
# Often caused by stale metadata
# Clean and try again
rm -rf .sfdx/
sf project retrieve start --target-org production
sf project deploy start --target-org production
```

**Issue:** Test failures during deployment

**Solution:**
```bash
# Run tests locally to debug
npm run test:apex -- --target-org production

# Fix failing tests
# Retest locally
# Resubmit deployment
```

**Issue:** Governor limits exceeded during deployment

**Solution:**
1. Reduce batch size in configuration
2. Split deployment into multiple jobs
3. Deploy to sandbox first to test

---

## Release Notes Template

**When deploying to production, create release notes:**

```markdown
# Release v1.0.0 - September 22, 2026

## Summary
Cortex Intelligence MVP deployment - customer churn prediction and segmentation platform.

## Features
- Real-time churn risk prediction (80%+ accuracy)
- RFM customer segmentation
- Interactive analytics dashboard
- REST API with OAuth 2.0
- Platform Events for real-time processing

## Improvements
- Query optimization with Platform Cache
- Batch processing for 1B+ records
- Enterprise security hardening

## Known Limitations
- BigObject queries limited to 100,000 records per query
- API rate limited to 1,000 requests/hour
- Predictions update nightly (real-time via API)

## Breaking Changes
None

## Upgrade Path
New system - no migration needed

## Support Contact
jinalraval2022@gmail.com
```

---

## Success Metrics

**Post-deployment, verify:**

- ✅ All users can access dashboard
- ✅ API endpoints responding within SLA
- ✅ Nightly batch jobs completing
- ✅ Error logs within acceptable range
- ✅ No performance degradation
- ✅ Security audit log populated

---

**Document Version:** 1.0  
**Last Updated:** September 22, 2026  
**Next Review:** After first production deployment
