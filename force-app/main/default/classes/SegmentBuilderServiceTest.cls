@IsTest
private class SegmentBuilderServiceTest {

    // RFM scoring logic is tested against classifyFromEvents directly, using
    // in-memory CustomerDataEvents__b instances that are never inserted -
    // Database.insertImmediate does not work inside the Apex test runner on
    // this org (see BigObjectWriter's class comment), so classifyAndUpdate's
    // own SOQL query can't be exercised end-to-end here.
    @IsTest
    static void testClassifyFromEventsAssignsHighMidLowSegments() {
        String highCustomer = 'TEST-Segment-High';
        String midCustomer = 'TEST-Segment-Mid';
        String lowCustomer = 'TEST-Segment-Low';
        String noPurchaseCustomer = 'TEST-Segment-NoPurchases';

        DateTime now = System.now();
        List<CustomerDataEvents__b> events = new List<CustomerDataEvents__b>();
        for (Integer i = 0; i < 5; i++) {
            events.add(new CustomerDataEvents__b(CustomerId__c = highCustomer, EventType__c = 'Purchase', EventTimestamp__c = now, Amount__c = 200));
        }
        for (Integer i = 0; i < 2; i++) {
            events.add(new CustomerDataEvents__b(CustomerId__c = midCustomer, EventType__c = 'Purchase', EventTimestamp__c = now.addDays(-30), Amount__c = 80));
        }
        events.add(new CustomerDataEvents__b(CustomerId__c = lowCustomer, EventType__c = 'Purchase', EventTimestamp__c = now.addDays(-170), Amount__c = 10));
        // noPurchaseCustomer has no matching events at all, exercising the
        // "customer has zero purchases in the window" branch (recency
        // defaults to the full lookback window rather than a computed delta).

        Set<String> customerIds = new Set<String>{ highCustomer, midCustomer, lowCustomer, noPurchaseCustomer };

        Test.startTest();
        List<SegmentBuilderService.RfmScore> scores = SegmentBuilderService.classifyFromEvents(customerIds, events);
        Test.stopTest();

        System.assertEquals(4, scores.size());

        Map<String, SegmentBuilderService.RfmScore> scoreByCustomer = new Map<String, SegmentBuilderService.RfmScore>();
        for (SegmentBuilderService.RfmScore score : scores) {
            scoreByCustomer.put(score.customerId, score);
        }

        System.assertEquals('High', scoreByCustomer.get(highCustomer).segment);
        System.assertEquals('Low', scoreByCustomer.get(lowCustomer).segment);
        System.assertEquals('Low', scoreByCustomer.get(noPurchaseCustomer).segment);
        System.assertEquals(180, scoreByCustomer.get(noPurchaseCustomer).recency);
    }

    @IsTest
    static void testUpdateProfilesAppliesSegments() {
        String customerId = 'TEST-Segment-ProfileUpdate';
        insert new CustomerProfile__c(ExternalCustomerId__c = customerId, CustomerSegment__c = 'Unclassified');

        SegmentBuilderService.RfmScore score = new SegmentBuilderService.RfmScore();
        score.customerId = customerId;
        score.segment = 'High';

        Test.startTest();
        SegmentBuilderService.updateProfiles(new List<SegmentBuilderService.RfmScore>{ score });
        Test.stopTest();

        CustomerProfile__c updated = [
            SELECT CustomerSegment__c
            FROM CustomerProfile__c
            WHERE ExternalCustomerId__c = :customerId
        ];
        System.assertEquals('High', updated.CustomerSegment__c);
    }

    @IsTest
    static void testClassifyAndUpdateWithEmptySetReturnsEmptyList() {
        Test.startTest();
        List<SegmentBuilderService.RfmScore> scores = SegmentBuilderService.classifyAndUpdate(new Set<String>());
        Test.stopTest();

        System.assertEquals(0, scores.size());
    }

    @IsTest
    static void testFindLookalikeCustomersReturnsClosestMatchFirst() {
        CustomerProfile__c seed = new CustomerProfile__c(
            ExternalCustomerId__c = 'TEST-Lookalike-Seed',
            CustomerSegment__c = 'High',
            ChurnRiskScore__c = 0.2,
            LifetimeValue__c = 5000
        );
        insert seed;

        CustomerProfile__c closeMatch = new CustomerProfile__c(
            ExternalCustomerId__c = 'TEST-Lookalike-Close',
            CustomerSegment__c = 'High',
            ChurnRiskScore__c = 0.22,
            LifetimeValue__c = 5100
        );
        CustomerProfile__c farMatch = new CustomerProfile__c(
            ExternalCustomerId__c = 'TEST-Lookalike-Far',
            CustomerSegment__c = 'High',
            ChurnRiskScore__c = 0.9,
            LifetimeValue__c = 100
        );
        CustomerProfile__c differentSegment = new CustomerProfile__c(
            ExternalCustomerId__c = 'TEST-Lookalike-DifferentSegment',
            CustomerSegment__c = 'Low',
            ChurnRiskScore__c = 0.21,
            LifetimeValue__c = 5050
        );
        insert new List<CustomerProfile__c>{ closeMatch, farMatch, differentSegment };

        Test.startTest();
        List<CustomerProfile__c> results = SegmentBuilderService.findLookalikeCustomers(seed.Id, 5);
        Test.stopTest();

        System.assertEquals(2, results.size());
        System.assertEquals(closeMatch.Id, results[0].Id);
    }

    @IsTest
    static void testFindLookalikeCustomersThrowsWhenSeedNotFound() {
        CustomerProfile__c temp = new CustomerProfile__c(ExternalCustomerId__c = 'TEST-Lookalike-Deleted');
        insert temp;
        Id deletedId = temp.Id;
        delete temp;

        Test.startTest();
        try {
            SegmentBuilderService.findLookalikeCustomers(deletedId, 5);
            System.assert(false, 'Expected an exception for a non-existent seed Id');
        } catch (CortexServiceException e) {
            System.assert(e.getMessage().contains('Seed CustomerProfile__c record not found'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testFindLookalikeCustomersRequiresSeedId() {
        Test.startTest();
        try {
            SegmentBuilderService.findLookalikeCustomers(null, 5);
            System.assert(false, 'Expected an exception for a null seed Id');
        } catch (CortexServiceException e) {
            System.assert(e.getMessage().contains('seed profile Id is required'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testQuerySegmentWithAllowedFieldSucceeds() {
        insert new CustomerProfile__c(
            ExternalCustomerId__c = 'TEST-QuerySegment',
            CustomerSegment__c = 'High'
        );

        Test.startTest();
        List<CustomerProfile__c> results = SegmentBuilderService.querySegment('CustomerSegment__c', '=', 'High', 10);
        Test.stopTest();

        System.assert(results.size() > 0);
    }

    @IsTest
    static void testQuerySegmentRejectsDisallowedField() {
        Test.startTest();
        try {
            SegmentBuilderService.querySegment('Name', '=', 'anything', 10);
            System.assert(false, 'Expected an exception for a disallowed field');
        } catch (CortexServiceException e) {
            System.assert(e.getMessage().contains('not permitted'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testQuerySegmentRejectsDisallowedOperator() {
        Test.startTest();
        try {
            SegmentBuilderService.querySegment('ChurnRiskScore__c', 'LIKE', 0.5, 10);
            System.assert(false, 'Expected an exception for a disallowed operator');
        } catch (CortexServiceException e) {
            System.assert(e.getMessage().contains('not permitted'));
        }
        Test.stopTest();
    }
}
