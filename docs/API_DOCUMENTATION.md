# Cortex Intelligence — REST API & Event Processing

**Version:** v1 · **Apex class:** `CortexRestAPI` · **Base URL:** `https://<my-domain>.my.salesforce.com/services/apexrest/cortex/v1`

---

## Authentication & access

All endpoints are Salesforce Apex REST, so every call needs an OAuth 2.0 access token:
`Authorization: Bearer <access_token>`. For server-to-server integrations, use the JWT bearer flow with a dedicated integration user.

Assign the integration user the **`Cortex_API_Integration`** permission set. It is least-privilege: it grants
access to the `CortexRestAPI` class, create/read on the Big Objects and Platform Events, create/read/edit on
`CustomerProfile__c`, and field-level security on the non-required fields. It grants no delete, View All or Modify All.

> **Field-level security is enforced on responses.** The deployed custom fields have no FLS on any profile,
> *including System Administrator*. A caller without the permission set gets `403 FORBIDDEN` from
> `/segments/rfm`. A caller with object access but no field access gets records with those fields left out.

---

## Endpoints

### `POST /events`: ingest customer events

The body can be a single event object, a JSON array of events, or `{"events": [...]}`. The limit is **200 events per request**.

| Field | Type | Required | Notes |
|---|---|---|---|
| `customerId` | string | ✅ | ≤ 50 chars |
| `eventType` | string | ✅ | ≤ 50 chars. `Purchase` and `SupportTicket` feed churn scoring; any other type counts as engagement |
| `eventId` | string | | ≤ 50 chars. **Idempotency key**: a replay with the same `customerId` + `eventId` returns `duplicate` |
| `eventTimestamp` | ISO-8601 string | | Defaults to the time the event is received |
| `eventSource` | string | | ≤ 50 chars |
| `amount` | number | | Used for monetary scoring on `Purchase` |
| `payload` | any JSON | | Stored as a JSON string, ≤ 32,768 chars |

```http
POST /services/apexrest/cortex/v1/events
Content-Type: application/json

{"events": [
  {"customerId": "CUST-1001", "eventType": "Purchase", "eventId": "ord-555", "amount": 120.50,
   "eventTimestamp": "2026-09-25T10:15:30Z", "payload": {"sku": "ABC-1"}},
  {"eventType": "Login"}
]}
```

```json
{
  "accepted": 1, "duplicates": 0, "rejected": 1,
  "results": [
    {"index": 0, "status": "created",  "eventId": "ord-555"},
    {"index": 1, "status": "rejected", "error": "CustomerId is required."}
  ]
}
```

| Status | Meaning |
|---|---|
| `201` | At least one event was created and none were rejected |
| `200` | Every event was a duplicate (an idempotent replay) |
| `207` | Mixed outcome. Check each item's `status` |
| `400` | Every event was rejected, or the body is malformed (`INVALID_JSON` / `BAD_REQUEST`) |
| `413` | More than 200 events in one request |

Each successfully stored event also publishes a `CustomerDataEvent__e`. That event triggers asynchronous churn re-scoring (see [Event processing](#event-processing)).

### `GET /predictions/churn/{customerId}`: real-time churn score

This endpoint scores the customer from the last 180 days of events. It also persists a `ChurnSignals__b` row, updates
`CustomerProfile__c.ChurnRiskScore__c` and publishes `ChurnAlertEvent__e` when the score is at or above
`CortexConfig__mdt.ChurnRiskThreshold__c`. URL-encode the ID if it contains reserved characters.

```json
{
  "customerId": "CUST-1001",
  "compositeRisk": 0.3300,
  "riskBucket": "Not At Risk",
  "atRisk": false,
  "recommendation": "No action required.",
  "factors": {"recency": 0, "frequency": 0.75, "monetary": 0, "engagement": 0.9, "support": 0},
  "generatedAt": "2026-09-25T14:09:05.306Z"
}
```

`400` means the ID is blank or longer than 50 chars. `503 PREDICTIONS_DISABLED` means `EnablePredictions__c` is off.

### `GET /segments/rfm?tier=HIGH&limit=200`: customers in an RFM tier

`tier` is required and must be `HIGH`, `MID` or `LOW` (case-insensitive). `limit` is optional, from 1 to 2000, and defaults to 200.

```json
{
  "tier": "HIGH", "count": 1,
  "customers": [{"id": "a05...", "name": "CP-0004", "externalCustomerId": "CUST-1001",
                 "segment": "High", "churnRiskScore": 0.33, "lifetimeValue": 1250.00}]
}
```

### Errors

Every error returns the same envelope. Stack traces are never returned; unexpected failures are logged at `ERROR` level and return a `500`.

```json
{"error": {"code": "NOT_FOUND", "message": "No resource at GET /cortex/v1/unknown"}}
```

Codes: `BAD_REQUEST`, `INVALID_JSON`, `FORBIDDEN` (403), `NOT_FOUND` (404),
`METHOD_NOT_ALLOWED` (405, with an `Allow` header), `PAYLOAD_TOO_LARGE` (413), `INTERNAL_ERROR` (500),
`PREDICTIONS_DISABLED` (503).

---

## Event processing

```
POST /events ─▶ DataIngestionService ─▶ CustomerDataEvents__b
                        │ (PublishAfterCommit)
                        ▼
              CustomerDataEvent__e ─▶ CustomerDataEventTrigger
                                          │ one job per delivered batch, distinct customers
                                          ▼
                              ChurnPredictionQueueable (100 customers per job, chains the rest)
                                          ▼
                              ChurnPredictionService.predictBulk ─▶ ChurnSignals__b,
                                          CustomerProfile__c, ChurnAlertEvent__e (≥ threshold)
```

- The trigger only enqueues work. Platform event triggers can't make callouts, and Big Object SOQL runs as a callout.
- If the enqueue fails, the trigger throws `EventBus.RetryableException` for up to 3 retries. After that the batch is logged and dropped. The nightly batch re-scores every customer, so a dropped event is only delayed, not lost.

## Batch jobs

| Job | Class | Default schedule (org time zone) |
|---|---|---|
| Nightly churn re-score | `ChurnPredictionBatch` | `0 0 2 * * ?` (02:00 daily) |
| Weekly RFM refresh | `SegmentRefreshBatch` | `0 0 3 ? * SUN` (03:00 Sunday) |

Scope size is `min(CortexConfig BatchSize__c, 200)`. Each chunk runs one Big Object query, and the cap keeps it
under the 50,000-row limit. A failing chunk is counted and logged, and the remaining chunks still run.

```apex
CortexJobScheduler.scheduleAll();    // idempotent: replaces existing Cortex schedules
CortexJobScheduler.unscheduleAll();
CortexJobScheduler.launch(CortexJobScheduler.Job.CHURN_PREDICTION); // run once, now
```

---

## Data-model constraint: Big Object index collisions

`CustomerDataEvents__b` is indexed on `(CustomerId__c, EventTimestamp__c)` only. A Big Object insert onto an
existing index key **silently overwrites** that row. To prevent this, `DataIngestionService` gives every event its own
slot. If the requested timestamp is already taken, either by a stored row or by an earlier event in the same request,
the event is moved forward to the next free millisecond. The stored timestamp can therefore differ from the one
you sent by a few milliseconds. This check happens before the insert, so two *concurrent* requests for the same
customer with the same millisecond timestamp can still race. Adding `EventId__c` to the index would remove the
problem entirely, but Big Object indexes can't be changed after deployment, so that fix needs a new Big Object.
