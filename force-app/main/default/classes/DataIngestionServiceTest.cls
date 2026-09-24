@IsTest
private class DataIngestionServiceTest {

    private static final String TEST_CUSTOMER_ID = 'TEST-Ingestion-Customer';

    // Big Object writes are routed through BigObjectWriter, which is a no-op
    // returning synthetic success in test context (Database.insertImmediate
    // does not work inside the Apex test runner on this org - see
    // BigObjectWriter's class comment). These tests therefore verify the
    // service's own orchestration logic (validation, dedup, result shape),
    // not that a record was actually persisted.
    @IsTest
    static void testSuccessfulIngestionWithGeneratedEventId() {
        List<CustomerEventInput> inputs = new List<CustomerEventInput>{
            new CustomerEventInput(TEST_CUSTOMER_ID, 'Login')
        };

        Test.startTest();
        List<IngestionResult> results = DataIngestionService.ingest(inputs);
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals(36, results[0].eventId.length());
    }

    @IsTest
    static void testValidationFailureMissingCustomerId() {
        List<CustomerEventInput> inputs = new List<CustomerEventInput>{
            new CustomerEventInput(null, 'Login')
        };

        Test.startTest();
        List<IngestionResult> results = DataIngestionService.ingest(inputs);
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assertEquals(false, results[0].isDuplicate);
        System.assertEquals('CustomerId is required.', results[0].errorMessage);
    }

    @IsTest
    static void testValidationFailureMissingEventType() {
        List<CustomerEventInput> inputs = new List<CustomerEventInput>{
            new CustomerEventInput(TEST_CUSTOMER_ID, null)
        };

        Test.startTest();
        List<IngestionResult> results = DataIngestionService.ingest(inputs);
        Test.stopTest();

        System.assertEquals(false, results[0].isSuccess);
        System.assertEquals('EventType is required.', results[0].errorMessage);
    }

    // Big Object SOQL is implemented as an external callout under the hood
    // (confirmed via Salesforce's own error: "The external callout is not
    // allowed in Apex test"), so DataIngestionService.queryExistingKeys can't
    // be exercised end-to-end in a test. The dedupe-matching logic itself is
    // isolated into matchExistingKeys and tested here against in-memory
    // CustomerDataEvents__b instances instead.
    @IsTest
    static void testMatchExistingKeysDetectsDuplicate() {
        Set<String> dedupeKeys = new Set<String>{ 'CUST-1|evt-a', 'CUST-1|evt-b' };
        List<CustomerDataEvents__b> candidates = new List<CustomerDataEvents__b>{
            new CustomerDataEvents__b(CustomerId__c = 'CUST-1', EventId__c = 'evt-a'),
            new CustomerDataEvents__b(CustomerId__c = 'CUST-2', EventId__c = 'evt-b')
        };

        Test.startTest();
        Set<String> found = DataIngestionService.matchExistingKeys(dedupeKeys, candidates);
        Test.stopTest();

        System.assertEquals(1, found.size());
        System.assert(found.contains('CUST-1|evt-a'), 'Expected the matching customer+eventId pair to be detected');
        System.assert(!found.contains('CUST-1|evt-b'), 'Should not match evt-b under the wrong customer');
    }

    @IsTest
    static void testMatchExistingKeysReturnsEmptyWhenNoCandidatesMatch() {
        Set<String> dedupeKeys = new Set<String>{ 'CUST-1|evt-a' };
        List<CustomerDataEvents__b> candidates = new List<CustomerDataEvents__b>{
            new CustomerDataEvents__b(CustomerId__c = 'CUST-1', EventId__c = 'evt-different')
        };

        Test.startTest();
        Set<String> found = DataIngestionService.matchExistingKeys(dedupeKeys, candidates);
        Test.stopTest();

        System.assertEquals(0, found.size());
    }

    @IsTest
    static void testBulkIngestionOfMixedValidAndInvalidEvents() {
        List<CustomerEventInput> inputs = new List<CustomerEventInput>{
            new CustomerEventInput(TEST_CUSTOMER_ID, 'Purchase'),
            new CustomerEventInput(null, 'Purchase'),
            new CustomerEventInput(TEST_CUSTOMER_ID, 'SupportTicket')
        };

        Test.startTest();
        List<IngestionResult> results = DataIngestionService.ingest(inputs);
        Test.stopTest();

        System.assertEquals(3, results.size());
        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals(false, results[1].isSuccess);
        System.assertEquals(true, results[2].isSuccess);
    }
}
