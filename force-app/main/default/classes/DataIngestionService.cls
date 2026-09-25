/**
 * Ingests customer events into the CustomerDataEvents__b Big Object.
 * Handles validation and EventId-based idempotency in bulk-safe fashion.
 * Big Objects don't support Apex triggers in this org, so the default-value
 * logic (timestamp/EventId generation) that would normally live in a
 * before-insert trigger is applied here instead.
 */
public with sharing class DataIngestionService {

    // Idempotency window: duplicate submissions/retries are expected to land
    // within days, not months, so the dedupe check only needs to look back
    // this far (keeps the Big Object query bounded for high-volume customers).
    private static final Integer DEDUPE_LOOKBACK_DAYS = 7;

    // Mirrors the CustomerDataEvents__b field definitions, so oversized values
    // are rejected per-event with a clear message instead of failing the write.
    public static final Integer MAX_TEXT_LENGTH = 50;
    public static final Integer MAX_PAYLOAD_LENGTH = 32768;

    public static List<IngestionResult> ingest(List<CustomerEventInput> events) {
        return ingest(events, false);
    }

    /**
     * @param publishNotifications when true, a CustomerDataEvent__e is
     *        published for every successfully stored event so downstream
     *        subscribers (churn re-scoring) react in near real time. Events
     *        are PublishAfterCommit, so nothing is announced if the caller's
     *        transaction rolls back.
     */
    public static List<IngestionResult> ingest(List<CustomerEventInput> events, Boolean publishNotifications) {
        if (events == null || events.isEmpty()) {
            return new List<IngestionResult>();
        }
        List<IngestionResult> results = new List<IngestionResult>();
        for (Integer i = 0; i < events.size(); i++) {
            results.add(null);
        }

        // One timestamp for the whole call: defaulted events then collide
        // deterministically and are spread 1ms apart in input order below.
        DateTime ingestTime = System.now();
        List<CustomerDataEvents__b> storedCandidates = queryStoredCandidates(events, ingestTime);

        Set<String> dedupeKeys = collectDedupeKeys(events);
        Set<String> existingKeys = dedupeKeys.isEmpty()
            ? new Set<String>()
            : matchExistingKeys(dedupeKeys, storedCandidates);

        // CustomerDataEvents__b is indexed on (CustomerId__c, EventTimestamp__c)
        // only, and a Big Object insert whose index key already exists silently
        // OVERWRITES that row. Two distinct events for the same customer at the
        // same millisecond would therefore lose one of them, so every record is
        // assigned a free index slot (see claimFreeTimestamp).
        Set<String> occupiedSlots = new Set<String>();
        for (CustomerDataEvents__b stored : storedCandidates) {
            occupiedSlots.add(slotKey(stored.CustomerId__c, stored.EventTimestamp__c));
        }

        List<CustomerDataEvents__b> recordsToInsert = new List<CustomerDataEvents__b>();
        List<Integer> insertableIndexes = new List<Integer>();
        List<String> insertedEventIds = new List<String>();

        for (Integer i = 0; i < events.size(); i++) {
            CustomerEventInput input = events[i];
            String validationError = validate(input);
            if (validationError != null) {
                results[i] = IngestionResult.failure(validationError);
                continue;
            }

            String eventId = String.isNotBlank(input.eventId) ? input.eventId : generateUuid();
            if (String.isNotBlank(input.eventId)) {
                // existingKeys covers prior transactions; adding each accepted
                // key also catches the same EventId repeated within this batch.
                String key = dedupeKey(input.customerId, eventId);
                if (existingKeys.contains(key)) {
                    results[i] = IngestionResult.duplicateEvent(eventId);
                    continue;
                }
                existingKeys.add(key);
            }

            recordsToInsert.add(new CustomerDataEvents__b(
                CustomerId__c = input.customerId,
                EventType__c = input.eventType,
                EventTimestamp__c = claimFreeTimestamp(
                    input.customerId,
                    input.eventTimestamp != null ? input.eventTimestamp : ingestTime,
                    occupiedSlots
                ),
                EventSource__c = input.eventSource,
                Amount__c = input.amount,
                Payload__c = input.payload,
                EventId__c = eventId
            ));
            insertableIndexes.add(i);
            insertedEventIds.add(eventId);
        }

        List<CustomerDataEvents__b> storedRecords = new List<CustomerDataEvents__b>();
        if (!recordsToInsert.isEmpty()) {
            List<BigObjectWriter.WriteResult> writeResults = BigObjectWriter.insertImmediate(recordsToInsert);
            for (Integer j = 0; j < writeResults.size(); j++) {
                Integer originalIndex = insertableIndexes[j];
                if (writeResults[j].isSuccess) {
                    results[originalIndex] = IngestionResult.success(insertedEventIds[j]);
                    storedRecords.add(recordsToInsert[j]);
                } else {
                    results[originalIndex] = IngestionResult.failure(writeResults[j].errorMessage);
                }
            }
        }

        if (publishNotifications == true && !storedRecords.isEmpty()) {
            publishIngestedNotifications(storedRecords);
        }

        return results;
    }

    private static void publishIngestedNotifications(List<CustomerDataEvents__b> storedRecords) {
        List<CustomerDataEvent__e> notifications = new List<CustomerDataEvent__e>();
        for (CustomerDataEvents__b record : storedRecords) {
            notifications.add(new CustomerDataEvent__e(
                CustomerId__c = record.CustomerId__c,
                EventId__c = record.EventId__c,
                EventType__c = record.EventType__c,
                EventTimestamp__c = record.EventTimestamp__c,
                EventSource__c = record.EventSource__c,
                Payload__c = record.Payload__c
            ));
        }
        // A failed notification must not fail ingestion: the event is already
        // durably stored and the nightly ChurnPredictionBatch re-scores every
        // customer, so a missed real-time trigger is self-healing.
        List<Database.SaveResult> publishResults = EventBus.publish(notifications);
        for (Integer i = 0; i < publishResults.size(); i++) {
            if (!publishResults[i].isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'CustomerDataEvent__e publish failed for event ' +
                    notifications[i].EventId__c + ': ' + publishResults[i].getErrors());
            }
        }
    }

    private static String validate(CustomerEventInput input) {
        if (input == null) {
            return 'Event input is required.';
        }
        if (String.isBlank(input.customerId)) {
            return 'CustomerId is required.';
        }
        if (String.isBlank(input.eventType)) {
            return 'EventType is required.';
        }
        if (input.customerId.length() > MAX_TEXT_LENGTH) {
            return 'CustomerId must be at most ' + MAX_TEXT_LENGTH + ' characters.';
        }
        if (input.eventType.length() > MAX_TEXT_LENGTH) {
            return 'EventType must be at most ' + MAX_TEXT_LENGTH + ' characters.';
        }
        if (input.eventSource != null && input.eventSource.length() > MAX_TEXT_LENGTH) {
            return 'EventSource must be at most ' + MAX_TEXT_LENGTH + ' characters.';
        }
        if (input.eventId != null && input.eventId.length() > MAX_TEXT_LENGTH) {
            return 'EventId must be at most ' + MAX_TEXT_LENGTH + ' characters.';
        }
        if (input.payload != null && input.payload.length() > MAX_PAYLOAD_LENGTH) {
            return 'Payload must be at most ' + MAX_PAYLOAD_LENGTH + ' characters.';
        }
        return null;
    }

    private static Set<String> collectDedupeKeys(List<CustomerEventInput> events) {
        Set<String> keys = new Set<String>();
        for (CustomerEventInput input : events) {
            if (input != null && String.isNotBlank(input.customerId) && String.isNotBlank(input.eventId)) {
                keys.add(dedupeKey(input.customerId, input.eventId));
            }
        }
        return keys;
    }

    // Single bounded fetch of the stored rows this call could clash with, used
    // both for EventId dedupe and for index-slot collision avoidance. Big
    // Object SOQL can only filter on indexed fields (CustomerId__c,
    // EventTimestamp__c), so EventId__c matching happens in matchExistingKeys
    // rather than in the WHERE clause. The window is the dedupe lookback,
    // widened to include the oldest client-supplied timestamp (backfills).
    // The query is, per Salesforce's own error text, an external callout
    // under the hood ("The external callout is not allowed in Apex test"), so
    // tests drive it through CustomerEventSelector's in-memory stub.
    private static List<CustomerDataEvents__b> queryStoredCandidates(List<CustomerEventInput> events, DateTime ingestTime) {
        Set<String> customerIds = new Set<String>();
        DateTime windowStart = ingestTime.addDays(-DEDUPE_LOOKBACK_DAYS);
        for (CustomerEventInput input : events) {
            if (input == null || String.isBlank(input.customerId) || input.customerId.length() > MAX_TEXT_LENGTH) {
                continue;
            }
            customerIds.add(input.customerId);
            if (input.eventTimestamp != null && input.eventTimestamp < windowStart) {
                windowStart = input.eventTimestamp;
            }
        }
        return CustomerEventSelector.selectSince(customerIds, windowStart);
    }

    /**
     * Returns the requested timestamp, or the next free millisecond after it
     * if that (customer, timestamp) index slot is already taken, and marks the
     * returned slot as occupied. The shift is at most a few milliseconds and
     * preserves input order for events sharing a timestamp.
     */
    @TestVisible
    private static DateTime claimFreeTimestamp(String customerId, DateTime requested, Set<String> occupiedSlots) {
        DateTime candidate = requested;
        while (occupiedSlots.contains(slotKey(customerId, candidate))) {
            candidate = DateTime.newInstance(candidate.getTime() + 1);
        }
        occupiedSlots.add(slotKey(customerId, candidate));
        return candidate;
    }

    private static String slotKey(String customerId, DateTime eventTimestamp) {
        return customerId + '|' + eventTimestamp.getTime();
    }

    @TestVisible
    private static Set<String> matchExistingKeys(Set<String> dedupeKeys, List<CustomerDataEvents__b> candidates) {
        Map<String, Set<String>> candidateEventIdsByCustomer = new Map<String, Set<String>>();
        for (String key : dedupeKeys) {
            List<String> parts = key.split('\\|', 2);
            if (!candidateEventIdsByCustomer.containsKey(parts[0])) {
                candidateEventIdsByCustomer.put(parts[0], new Set<String>());
            }
            candidateEventIdsByCustomer.get(parts[0]).add(parts[1]);
        }

        Set<String> found = new Set<String>();
        for (CustomerDataEvents__b record : candidates) {
            Set<String> candidateEventIds = candidateEventIdsByCustomer.get(record.CustomerId__c);
            if (candidateEventIds != null && candidateEventIds.contains(record.EventId__c)) {
                found.add(dedupeKey(record.CustomerId__c, record.EventId__c));
            }
        }
        return found;
    }

    private static String dedupeKey(String customerId, String eventId) {
        return customerId + '|' + eventId;
    }

    private static String generateUuid() {
        Blob randomBlob = Crypto.generateAesKey(128);
        String hex = EncodingUtil.convertToHex(randomBlob);
        return hex.substring(0, 8) + '-' + hex.substring(8, 12) + '-' +
            hex.substring(12, 16) + '-' + hex.substring(16, 20) + '-' + hex.substring(20);
    }
}
