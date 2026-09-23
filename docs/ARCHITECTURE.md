# Cortex Intelligence: System Architecture

**Version:** 1.0  
**Date:** September 22, 2026  
**Salesforce Release:** Winter 2027 (API v61.0)

---

## Executive Summary

Cortex Intelligence is an enterprise-grade customer intelligence platform built on Salesforce. It processes massive customer datasets (1B+ records), performs real-time predictive analytics, and orchestrates intelligent customer journeys through automated workflows.

The platform is designed for scalability, security, and performance—targeting sub-500ms API response times, sub-2s dashboard loads, and 80%+ prediction accuracy.

---

## Architecture Overview

### Six-Layer Design Pattern

Cortex Intelligence follows a clean, layered architecture that separates concerns and enables independent scaling:

#### **Layer 1: Data Ingestion**
*Entry point for all customer data*

- **REST API** (OAuth 2.0): Receive events from web, mobile, and 3rd-party systems
- **Platform Events** (Pub/Sub): Real-time event streaming with guaranteed delivery
- **Webhooks**: Integration with Zapier, Make, and custom systems
- **Change Data Capture (CDC)**: Automatic sync of Salesforce data changes
- **Batch Imports**: Support for bulk historical data loading

**Key Components:**
- `CortexRestAPI` (Apex REST endpoint)
- `DataIngestionService` (validation, deduplication, BigObject insert)
- Event publishing with idempotency checks

#### **Layer 2: Unified Data Model**
*Centralized customer data repository*

**BigObjects** (High-volume, time-series):
- `CustomerDataEvents__b` - Customer event stream (purchases, logins, support tickets)
- `ChurnSignals__b` - Calculated churn risk indicators
- Indexed for efficient querying on `CustomerId__c` + `EventTimestamp__c`

**Custom Objects** (Transactional):
- `CustomerProfile__c` - Customer master data
- Fields: ExternalCustomerId__c, Email__c, LifetimeValue__c, CustomerSegment__c, ChurnRiskScore__c
- Linked to standard Account object

**Caching:**
- Platform Cache (5-10 MB) for frequent queries
- Automatic invalidation on data changes

**Configuration:**
- Custom Metadata Type: `CortexConfig__mdt`
- Stored settings: batch sizes, thresholds, feature flags, retention policies

#### **Layer 3: Intelligence Engine**
*Predictive models and audience segmentation*

**Churn Prediction Service:**
```
Input: Customer historical data
↓
Calculate Risk Factors:
  - Recency Risk (30%): Days since last purchase
  - Frequency Risk (20%): Purchase frequency
  - Monetary Risk (15%): Average order value
  - Engagement Risk (20%): Activity level
  - Support Risk (15%): Support ticket count
↓
Output: Composite risk score (0-1) + recommendation
```

**Accuracy Target:** > 80% precision using ensemble approach

**Segment Builder:**
- RFM segmentation (High/Mid/Low value)
- Lookalike audience (similar customers to seed)
- Churn risk buckets (70-80%, 80-90%, 90-100%)
- Custom segment queries via dynamic SOQL

**Processing:**
- Real-time calculations (API endpoint)
- Nightly batch predictions (Scheduled Apex)
- Incremental updates on new events

#### **Layer 4: Orchestration & Activation**
*Automated workflows and event-driven responses*

**Platform Events Triggers:**
- `CustomerDataEvent__e`: Published when event ingested → trigger predictions
- `ChurnAlertEvent__e`: Published when churn risk exceeds threshold → notify team

**Salesforce Flows:**
- Update customer segment based on churn score
- Send email/SMS alerts to account managers
- Trigger loyalty program rules
- Update CRM records in real-time

**External Webhooks:**
- Dispatch events to Zapier/Make
- Sync data to data warehouse (Snowflake, BigQuery)
- Trigger CDP integrations (mParticle, Segment)
- Feed into email platforms (Marketo, HubSpot)

**Batch Processing:**
- Nightly churn prediction recalculation
- Weekly segmentation refresh
- Monthly retention cohort analysis
- Configurable via Custom Metadata

#### **Layer 5: Analytics & Visualization**
*Executive dashboards and customer insights*

**LWC Components:**
- `cortexDashboard`: Main analytics dashboard
- `churnRiskGauge`: Risk visualization with custom SVG
- `cortexCard`: Reusable metric card component
- Custom charts (churn distribution, RFM breakdown)

**Metrics Displayed:**
- Customers at risk count
- RFM segment distribution
- Churn prediction accuracy
- Real-time recommendations per customer

**Performance:**
- Dashboard load time: < 2 seconds (with caching)
- Charts render via Canvas API for performance
- Query optimization via Platform Cache

#### **Layer 6: API & Integration Layer**
*External integrations and security*

**REST API Endpoints:**
```
POST /cortex/v1/events
GET  /cortex/v1/predictions/churn/{customerId}
GET  /cortex/v1/segments/rfm?tier=HIGH
```

**Authentication:**
- OAuth 2.0 with JWT bearer tokens
- Token validation and expiration checks
- IP whitelisting support (for integrations)

**Rate Limiting:**
- 1,000 requests/hour per API key
- Automatic backoff on 429 responses
- Request header tracking

**Monitoring:**
- Audit logging on all mutations
- API call tracking
- Error rate monitoring
- Performance metrics (response time, throughput)

---

## Data Flow Diagram

```
External Systems
    ↓
[REST API / Webhooks / CDC]
    ↓
[Data Ingestion Service]
    ├─ Validation
    ├─ Deduplication
    └─ BigObject Insert
    ↓
[Platform Event Published]
    ↓
[Event Handler / Trigger]
    ├─ Churn Prediction
    ├─ Segment Update
    └─ Risk Assessment
    ↓
[Publish Alert Event]
    ↓
[Salesforce Flows]
    ├─ Email notifications
    ├─ Update CRM records
    └─ Webhook dispatch
    ↓
[External Systems]
    ├─ Email platform
    ├─ Data warehouse
    └─ Analytics tools
```

---

## Security Model

### Authentication & Authorization

**API Authentication:**
```apex
// OAuth 2.0 Bearer token required
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

**Token Validation:**
- JWT signature verification
- Token expiration check (24-hour TTL)
- Issuer and audience validation

**Row-Level Security:**
- Salesforce sharing rules enforce field access
- API returns only authorized records
- User's org context honored

**Field-Level Security:**
- Encrypted fields (PII): SSN, payment info
- Automatic encryption/decryption in Apex
- Database encryption at rest

### Data Protection

**Encryption:**
```apex
// PII encryption with AES-256
Blob encrypted = Crypto.encryptWithManagedIV('AES256', key, data);
```

**Audit Logging:**
```apex
// All mutations tracked
AuditLog__c log = new AuditLog__c(
    Entity__c = 'CustomerProfile__c',
    Operation__c = 'UPDATE',
    UserId__c = UserInfo.getUserId(),
    IpAddress__c = getClientIp(),
    Timestamp__c = System.now()
);
insert log;
```

### Threat Prevention

**SOQL Injection:**
```apex
// ❌ Vulnerable
String query = 'SELECT * FROM Account WHERE Name = ' + userInput;

// ✅ Safe
String query = 'SELECT * FROM Account WHERE Name = :userInput';
```

**Cross-Site Scripting (XSS):**
- LWC automatic escaping of dynamic content
- No `innerHTML` without sanitization

**Rate Limiting:**
- API endpoint throttles to 1,000 req/hour
- Implements exponential backoff on retries
- Protects against brute force attacks

---

## Scalability Considerations

### Data Volume Handling

**BigObjects for Volume:**
- Supports 1B+ records per object
- Indexed on key fields (CustomerId__c, EventTimestamp__c)
- Optimized query performance even at scale

**Query Optimization:**
```apex
// ✅ Efficient - uses indexed fields
SELECT Id FROM CustomerDataEvent__b
WHERE CustomerId__c = :customerId
  AND EventTimestamp__c >= LAST_N_DAYS:90
LIMIT 10000
```

**Batch Processing:**
- Process 10,000 records per batch (configurable)
- Nightly scheduled jobs
- Retry mechanism for failed batches

**Caching Strategy:**
- Platform Cache for frequently accessed data
- 1-hour TTL for segment queries
- Automatic invalidation on data changes

### Horizontal Scaling

**Stateless API Design:**
- No session data in Apex
- Each request is independent
- Enables Salesforce load balancing

**Asynchronous Processing:**
- Platform Events publish immediately (non-blocking)
- Queueable jobs for retries
- Scheduled jobs for batch operations

### Governor Limit Awareness

| Limit | Strategy |
|-------|----------|
| SOQL Queries (100) | Batch queries, Platform Cache |
| DML Statements (150) | Batch updates, collected DML |
| Heap Size (6MB) | Streaming results, memory optimization |
| CPU Time (10s) | Async processing via Queueable |
| Callouts (100) | Webhook dispatch via Queueable |

---

## Performance Targets

| Metric | Target | Strategy |
|--------|--------|----------|
| API response time | < 500ms (95th) | Query optimization, caching |
| Dashboard load | < 2s | Platform Cache, aggregated queries |
| Batch job duration | < 1 hour | 10k records/batch, nightly window |
| Prediction accuracy | > 80% | Ensemble of 5 risk factors |
| Concurrent users | 100+ | Stateless APIs, load balancing |

---

## Technology Stack

| Component | Technology | Version | Rationale |
|-----------|-----------|---------|-----------|
| Platform | Salesforce | Winter 2027 | Latest features, long-term support |
| Language | Apex | 61.0 | Native Salesforce, zero external dependencies |
| Frontend | LWC | v7.0+ | Modern, reactive framework |
| Database | BigObjects | Native | Designed for massive data volumes |
| APIs | REST (Salesforce) | Native | Built-in security, OAuth 2.0 |
| CI/CD | GitHub Actions | Latest | Integrated workflows, free tier |
| Testing | Jest + Apex | Latest | Industry standard, high coverage |
| Monitoring | Custom | Apex | Audit logs, error tracking |

---

## Disaster Recovery & High Availability

**Backup Strategy:**
- Automatic Salesforce backups (daily)
- BigObject data retention (2 years configurable)
- Change Data Capture for point-in-time recovery

**Rollback Procedure:**
```bash
# If deployment fails
git revert HEAD
sf project deploy start --target-org production
```

**Data Integrity Checks:**
- Idempotent event processing (EventId as dedup key)
- Checksum validation for imports
- Regular data reconciliation jobs

---

## Future Enhancements

- **Phase 2:** Machine Learning integration (predictive models)
- **Phase 3:** Multi-channel orchestration (email, SMS, push)
- **Phase 4:** Advanced analytics (Salesforce Analytics Cloud)
- **Phase 5:** Mobile app (customer 360 view)

---

**Document Version:** 1.0  
**Last Updated:** September 22, 2026  
**Next Review:** Q1 2027
