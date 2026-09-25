/**
 * Single read path for CustomerDataEvents__b history.
 *
 * Big Object SOQL can only filter on the index (CustomerId__c, then
 * EventTimestamp__c), and is implemented as an external callout under the
 * hood, so it cannot be relied on inside the Apex test runner (see
 * DataIngestionService.queryExistingKeys). Centralising the query here gives
 * batch/queueable/REST callers one bulk-safe fetch per transaction, and gives
 * tests a seam: when stubbedEvents is set, the selector filters that
 * in-memory list with the same semantics instead of querying.
 */
public with sharing class CustomerEventSelector {

    // Heap/row-limit guard: one transaction never pulls more event history
    // than this, regardless of how many customers are in scope.
    public static final Integer MAX_ROWS = 50000;

    @TestVisible
    private static List<CustomerDataEvents__b> stubbedEvents;

    public static List<CustomerDataEvents__b> selectSince(Set<String> customerIds, DateTime windowStart) {
        if (customerIds == null || customerIds.isEmpty()) {
            return new List<CustomerDataEvents__b>();
        }
        if (stubbedEvents != null) {
            return filterStub(customerIds, windowStart);
        }
        return [
            SELECT CustomerId__c, EventId__c, EventType__c, EventTimestamp__c, Amount__c
            FROM CustomerDataEvents__b
            WHERE CustomerId__c IN :customerIds AND EventTimestamp__c >= :windowStart
            LIMIT :MAX_ROWS
        ];
    }

    private static List<CustomerDataEvents__b> filterStub(Set<String> customerIds, DateTime windowStart) {
        List<CustomerDataEvents__b> matches = new List<CustomerDataEvents__b>();
        for (CustomerDataEvents__b event : stubbedEvents) {
            if (customerIds.contains(event.CustomerId__c) && event.EventTimestamp__c >= windowStart) {
                matches.add(event);
            }
        }
        return matches;
    }
}
