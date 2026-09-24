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

    public static List<IngestionResult> ingest(List<CustomerEventInput> events) {
        List<IngestionResult> results = new List<IngestionResult>();
        for (Integer i = 0; i < events.size(); i++) {
            results.add(null);
        }

        Set<String> dedupeKeys = collectDedupeKeys(events);
        Set<String> existingKeys = dedupeKeys.isEmpty() ? new Set<String>() : queryExistingKeys(dedupeKeys);

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
            if (String.isNotBlank(input.eventId) && existingKeys.contains(dedupeKey(input.customerId, eventId))) {
                results[i] = IngestionResult.duplicateEvent(eventId);
                continue;
            }

            recordsToInsert.add(new CustomerDataEvents__b(
                CustomerId__c = input.customerId,
                EventType__c = input.eventType,
                EventTimestamp__c = input.eventTimestamp != null ? input.eventTimestamp : System.now(),
                EventSource__c = input.eventSource,
                Amount__c = input.amount,
                Payload__c = input.payload,
                EventId__c = eventId
            ));
            insertableIndexes.add(i);
            insertedEventIds.add(eventId);
        }

        if (!recordsToInsert.isEmpty()) {
            List<BigObjectWriter.WriteResult> writeResults = BigObjectWriter.insertImmediate(recordsToInsert);
            for (Integer j = 0; j < writeResults.size(); j++) {
                Integer originalIndex = insertableIndexes[j];
                if (writeResults[j].isSuccess) {
                    results[originalIndex] = IngestionResult.success(insertedEventIds[j]);
                } else {
                    results[originalIndex] = IngestionResult.failure(writeResults[j].errorMessage);
                }
            }
        }

        return results;
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

    // Big Object SOQL can only filter on indexed fields (CustomerId__c,
    // EventTimestamp__c), so EventId__c matching happens in matchExistingKeys
    // after a bounded-by-time fetch, rather than in the WHERE clause. The
    // query itself is also, per Salesforce's own error text, implemented as
    // an external callout under the hood ("The external callout is not
    // allowed in Apex test"), so it cannot be exercised inside an Apex test
    // at all; the matching logic is isolated into matchExistingKeys below so
    // it can still be unit tested against in-memory data.
    private static Set<String> queryExistingKeys(Set<String> dedupeKeys) {
        Set<String> customerIds = new Set<String>();
        for (String key : dedupeKeys) {
            customerIds.add(key.split('\\|', 2)[0]);
        }

        DateTime dedupeWindowStart = System.now().addDays(-DEDUPE_LOOKBACK_DAYS);
        List<CustomerDataEvents__b> candidates = [
            SELECT CustomerId__c, EventId__c
            FROM CustomerDataEvents__b
            WHERE CustomerId__c IN :customerIds AND EventTimestamp__c >= :dedupeWindowStart
        ];
        return matchExistingKeys(dedupeKeys, candidates);
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
