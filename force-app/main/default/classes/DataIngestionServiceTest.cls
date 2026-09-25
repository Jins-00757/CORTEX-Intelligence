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

    @IsTest
    static void testNullOrEmptyInputReturnsEmptyResults() {
        System.assertEquals(0, DataIngestionService.ingest(null).size());
        System.assertEquals(0, DataIngestionService.ingest(new List<CustomerEventInput>()).size());
    }

    @IsTest
    static void testFieldLengthLimitsAreEnforced() {
        String tooLong = 'x'.repeat(DataIngestionService.MAX_TEXT_LENGTH + 1);
        CustomerEventInput longCustomer = new CustomerEventInput(tooLong, 'Login');
        CustomerEventInput longType = new CustomerEventInput(TEST_CUSTOMER_ID, tooLong);
        CustomerEventInput longSource = new CustomerEventInput(TEST_CUSTOMER_ID, 'Login');
        longSource.eventSource = tooLong;
        CustomerEventInput longEventId = new CustomerEventInput(TEST_CUSTOMER_ID, 'Login');
        longEventId.eventId = tooLong;
        CustomerEventInput longPayload = new CustomerEventInput(TEST_CUSTOMER_ID, 'Login');
        longPayload.payload = 'x'.repeat(DataIngestionService.MAX_PAYLOAD_LENGTH + 1);
        CortexTestUtils.stubEvents(null);

        Test.startTest();
        List<IngestionResult> results = DataIngestionService.ingest(new List<CustomerEventInput>{
            longCustomer, longType, longSource, longEventId, longPayload
        });
        Test.stopTest();

        System.assert(results[0].errorMessage.startsWith('CustomerId must be at most'));
        System.assert(results[1].errorMessage.startsWith('EventType must be at most'));
        System.assert(results[2].errorMessage.startsWith('EventSource must be at most'));
        System.assert(results[3].errorMessage.startsWith('EventId must be at most'));
        System.assert(results[4].errorMessage.startsWith('Payload must be at most'));
    }

    @IsTest
    static void testDuplicateEventIdsAreDetectedAgainstHistoryAndWithinBatch() {
        CortexTestUtils.stubEvents(new List<CustomerDataEvents__b>{
            new CustomerDataEvents__b(CustomerId__c = TEST_CUSTOMER_ID, EventId__c = 'evt-stored', EventTimestamp__c = System.now().addDays(-1))
        });
        CustomerEventInput stored = new CustomerEventInput(TEST_CUSTOMER_ID, 'Login');
        stored.eventId = 'evt-stored';
        CustomerEventInput first = new CustomerEventInput(TEST_CUSTOMER_ID, 'Login');
        first.eventId = 'evt-new';
        CustomerEventInput repeated = new CustomerEventInput(TEST_CUSTOMER_ID, 'Login');
        repeated.eventId = 'evt-new';

        Test.startTest();
        List<IngestionResult> results = DataIngestionService.ingest(new List<CustomerEventInput>{ stored, first, repeated });
        Test.stopTest();

        System.assertEquals(true, results[0].isDuplicate);
        System.assertEquals(true, results[1].isSuccess);
        System.assertEquals('evt-new', results[1].eventId);
        System.assertEquals(true, results[2].isDuplicate);
    }

    // Regression: CustomerDataEvents__b is indexed on (CustomerId__c,
    // EventTimestamp__c) only, and a Big Object insert onto an existing index
    // key overwrites that row. Found in the Day 4 end-to-end smoke test, where
    // two events ingested in one request got the same System.now() and the
    // first was silently lost.
    @IsTest
    static void testEventsSharingAnIndexSlotAreGivenDistinctTimestamps() {
        DateTime clientTimestamp = DateTime.newInstanceGmt(2026, 9, 20, 10, 15, 30);
        CortexTestUtils.stubEvents(new List<CustomerDataEvents__b>{
            new CustomerDataEvents__b(CustomerId__c = TEST_CUSTOMER_ID, EventId__c = 'already-stored', EventTimestamp__c = clientTimestamp)
        });
        CustomerEventInput clashesWithStored = new CustomerEventInput(TEST_CUSTOMER_ID, 'Purchase');
        clashesWithStored.eventTimestamp = clientTimestamp;
        CustomerEventInput defaultedA = new CustomerEventInput(TEST_CUSTOMER_ID, 'Login');
        CustomerEventInput defaultedB = new CustomerEventInput(TEST_CUSTOMER_ID, 'Login');
        CustomerEventInput otherCustomer = new CustomerEventInput('TEST-Other-Customer', 'Purchase');
        otherCustomer.eventTimestamp = clientTimestamp;

        Test.startTest();
        List<IngestionResult> results = DataIngestionService.ingest(new List<CustomerEventInput>{
            clashesWithStored, defaultedA, defaultedB, otherCustomer
        });
        Test.stopTest();

        for (IngestionResult result : results) {
            System.assertEquals(true, result.isSuccess);
        }
        List<CustomerDataEvents__b> written = new List<CustomerDataEvents__b>();
        for (SObject record : BigObjectWriter.recordsWrittenInTest) {
            written.add((CustomerDataEvents__b) record);
        }
        System.assertEquals(4, written.size());
        System.assertEquals(clientTimestamp.getTime() + 1, written[0].EventTimestamp__c.getTime(),
            'Must move past the already-stored row rather than overwrite it');
        System.assertEquals(written[1].EventTimestamp__c.getTime() + 1, written[2].EventTimestamp__c.getTime(),
            'Same-call defaulted timestamps must be spread 1ms apart in input order');
        System.assertEquals(clientTimestamp, written[3].EventTimestamp__c,
            'A different customer occupies a different index slot and keeps its timestamp');
    }

    @IsTest
    static void testClaimFreeTimestampSkipsOccupiedSlots() {
        DateTime requested = DateTime.newInstance(1000000);
        Set<String> occupied = new Set<String>{ 'C|1000000', 'C|1000001' };

        DateTime claimed = DataIngestionService.claimFreeTimestamp('C', requested, occupied);

        System.assertEquals(1000002, claimed.getTime());
        System.assert(occupied.contains('C|1000002'), 'The claimed slot must be marked occupied');
    }

    @IsTest
    static void testIngestWithNotificationsPublishesForStoredEventsOnly() {
        CortexTestUtils.disablePredictions(); // keep the subscriber from re-scoring
        List<CustomerEventInput> inputs = new List<CustomerEventInput>{
            new CustomerEventInput(TEST_CUSTOMER_ID, 'Login'),
            new CustomerEventInput(null, 'Login')
        };

        Test.startTest();
        List<IngestionResult> results = DataIngestionService.ingest(inputs, true);
        Integer dmlAfterPublish = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(true, results[0].isSuccess);
        System.assertEquals(false, results[1].isSuccess);
        System.assertEquals(1, dmlAfterPublish, 'Exactly one EventBus.publish for the stored event');
    }
}
