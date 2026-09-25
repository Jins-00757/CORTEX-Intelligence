// Big Object writes are routed through BigObjectWriter, which is a no-op
// returning synthetic success in test context (Database.insertImmediate does
// not work inside the Apex test runner on this org - see BigObjectWriter's
// class comment for the confirmed platform limitation). The weighted risk
// math is therefore tested directly against calculate(), using in-memory
// CustomerDataEvents__b instances that are never inserted, so no Big Object
// I/O is needed to verify the calculation itself.
@IsTest
private class ChurnPredictionServiceTest {

    @IsTest
    static void testCalculateHealthyCustomerYieldsZeroCompositeRisk() {
        String customerId = 'TEST-Churn-Healthy';
        DateTime now = System.now();

        List<CustomerDataEvents__b> events = new List<CustomerDataEvents__b>();
        for (Integer i = 0; i < 4; i++) {
            events.add(new CustomerDataEvents__b(
                CustomerId__c = customerId,
                EventType__c = 'Purchase',
                EventTimestamp__c = now,
                Amount__c = 100
            ));
        }
        for (Integer i = 0; i < 10; i++) {
            events.add(new CustomerDataEvents__b(
                CustomerId__c = customerId,
                EventType__c = 'Login',
                EventTimestamp__c = now
            ));
        }

        Test.startTest();
        ChurnPredictionService.ChurnPredictionResult result = ChurnPredictionService.calculate(customerId, events);
        Test.stopTest();

        System.assertEquals(0, result.compositeRisk);
        System.assertEquals('Not At Risk', result.riskBucket);
    }

    @IsTest
    static void testCalculateModerateActivityMatchesWeightedFormula() {
        String customerId = 'TEST-Churn-Moderate';
        DateTime now = System.now();

        List<CustomerDataEvents__b> events = new List<CustomerDataEvents__b>{
            new CustomerDataEvents__b(CustomerId__c = customerId, EventType__c = 'Purchase', EventTimestamp__c = now.addDays(-45), Amount__c = 50),
            new CustomerDataEvents__b(CustomerId__c = customerId, EventType__c = 'Purchase', EventTimestamp__c = now.addDays(-90), Amount__c = 50)
        };
        for (Integer i = 0; i < 5; i++) {
            events.add(new CustomerDataEvents__b(CustomerId__c = customerId, EventType__c = 'Login', EventTimestamp__c = now));
        }
        for (Integer i = 0; i < 5; i++) {
            events.add(new CustomerDataEvents__b(CustomerId__c = customerId, EventType__c = 'SupportTicket', EventTimestamp__c = now));
        }

        Test.startTest();
        ChurnPredictionService.ChurnPredictionResult result = ChurnPredictionService.calculate(customerId, events);
        Test.stopTest();

        System.assertEquals(0.575, result.compositeRisk);
        System.assertEquals('Not At Risk', result.riskBucket);
    }

    @IsTest
    static void testCalculateNoActivityYieldsHighRisk() {
        Test.startTest();
        ChurnPredictionService.ChurnPredictionResult result = ChurnPredictionService.calculate(
            'TEST-Churn-NoActivity', new List<CustomerDataEvents__b>()
        );
        Test.stopTest();

        System.assertEquals(0.85, result.compositeRisk);
        System.assertEquals('80-90%', result.riskBucket);
    }

    @IsTest
    static void testCalculateExcessSupportTicketsClampsToMaxRiskBucket() {
        // No purchases/engagement (max risk on those factors) plus support
        // tickets exceeding SUPPORT_TICKET_CEILING, which also exercises the
        // minOne() >1 clamp (6/5 ratio) rather than a same-scale 0-1 value.
        String customerId = 'TEST-Churn-MaxRisk';
        DateTime now = System.now();
        List<CustomerDataEvents__b> events = new List<CustomerDataEvents__b>();
        for (Integer i = 0; i < 6; i++) {
            events.add(new CustomerDataEvents__b(CustomerId__c = customerId, EventType__c = 'SupportTicket', EventTimestamp__c = now));
        }

        Test.startTest();
        ChurnPredictionService.ChurnPredictionResult result = ChurnPredictionService.calculate(customerId, events);
        Test.stopTest();

        System.assertEquals(1, result.compositeRisk);
        System.assertEquals('90-100%', result.riskBucket);
    }

    @IsTest
    static void testCalculateModerateSupportBurdenYields70To80RiskBucket() {
        String customerId = 'TEST-Churn-SeventyRange';
        DateTime now = System.now();
        List<CustomerDataEvents__b> events = new List<CustomerDataEvents__b>();
        for (Integer i = 0; i < 10; i++) {
            events.add(new CustomerDataEvents__b(CustomerId__c = customerId, EventType__c = 'Login', EventTimestamp__c = now));
        }
        for (Integer i = 0; i < 2; i++) {
            events.add(new CustomerDataEvents__b(CustomerId__c = customerId, EventType__c = 'SupportTicket', EventTimestamp__c = now));
        }

        Test.startTest();
        ChurnPredictionService.ChurnPredictionResult result = ChurnPredictionService.calculate(customerId, events);
        Test.stopTest();

        System.assertEquals(0.71, result.compositeRisk);
        System.assertEquals('70-80%', result.riskBucket);
    }

    @IsTest
    static void testPublishAlertIfNeededSkipsBelowThreshold() {
        ChurnPredictionService.ChurnPredictionResult result = new ChurnPredictionService.ChurnPredictionResult();
        result.customerId = 'TEST-Churn-NoAlert';
        result.compositeRisk = 0.1;
        result.riskBucket = 'Not At Risk';
        result.recommendation = 'No action required.';

        Test.startTest();
        ChurnPredictionService.publishAlertIfNeeded(result);
        Test.stopTest();
        // No assertion beyond "completes without error": below the configured
        // threshold, EventBus.publish must not be reached.
    }

    @IsTest
    static void testPredictEndToEndForCustomerWithNoHistory() {
        // No pre-existing data needed for this scenario, so predict() can run
        // its full pipeline (query, calculate, persist via BigObjectWriter,
        // profile lookup, alert check) without touching real Big Object data.
        String customerId = 'TEST-Churn-Predict-NoHistory';

        Test.startTest();
        ChurnPredictionService.ChurnPredictionResult result = ChurnPredictionService.predict(customerId);
        Test.stopTest();

        System.assertEquals(0.85, result.compositeRisk);
        System.assertEquals('80-90%', result.riskBucket);
    }

    @IsTest
    static void testUpdateCustomerProfileAppliesComputedScore() {
        String customerId = 'TEST-Churn-ProfileUpdate';
        insert new CustomerProfile__c(
            ExternalCustomerId__c = customerId
        );

        ChurnPredictionService.ChurnPredictionResult result = new ChurnPredictionService.ChurnPredictionResult();
        result.customerId = customerId;
        result.compositeRisk = 0.85;

        Test.startTest();
        ChurnPredictionService.updateCustomerProfile(result);
        Test.stopTest();

        CustomerProfile__c updated = [
            SELECT ChurnRiskScore__c
            FROM CustomerProfile__c
            WHERE ExternalCustomerId__c = :customerId
        ];
        System.assertEquals(0.85, updated.ChurnRiskScore__c);
    }

    @IsTest
    static void testUpdateCustomerProfileNoOpWhenProfileMissing() {
        ChurnPredictionService.ChurnPredictionResult result = new ChurnPredictionService.ChurnPredictionResult();
        result.customerId = 'TEST-Churn-NoMatchingProfile';
        result.compositeRisk = 0.5;

        Test.startTest();
        ChurnPredictionService.updateCustomerProfile(result);
        Test.stopTest();

        System.assertEquals(0, [
            SELECT COUNT() FROM CustomerProfile__c WHERE ExternalCustomerId__c = :result.customerId
        ]);
    }

    @IsTest
    static void testBlankCustomerIdThrows() {
        Test.startTest();
        try {
            ChurnPredictionService.predict('');
            System.assert(false, 'Expected an exception for a blank customerId');
        } catch (CortexServiceException e) {
            System.assert(e.getMessage().contains('CustomerId is required'));
        }
        Test.stopTest();
    }

    @IsTest
    static void testPredictBulkScoresEachCustomerFromOneEventFetch() {
        CortexTestUtils.insertProfiles(new List<String>{ 'BULK-AT-RISK', 'BULK-HEALTHY' });
        CortexTestUtils.stubEvents(CortexTestUtils.healthyHistory('BULK-HEALTHY'));

        Test.startTest();
        List<ChurnPredictionService.ChurnPredictionResult> results = ChurnPredictionService.predictBulk(
            new Set<String>{ 'BULK-AT-RISK', 'BULK-HEALTHY', '', null }
        );
        Test.stopTest();

        System.assertEquals(2, results.size(), 'Blank ids must be ignored');
        Map<String, CustomerProfile__c> profiles = CortexTestUtils.profilesByExternalId();
        System.assertEquals(0.85, profiles.get('BULK-AT-RISK').ChurnRiskScore__c);
        System.assertEquals(0, profiles.get('BULK-HEALTHY').ChurnRiskScore__c);
    }

    @IsTest
    static void testPredictBulkWithNoCustomersReturnsEmpty() {
        System.assertEquals(0, ChurnPredictionService.predictBulk(null).size());
        System.assertEquals(0, ChurnPredictionService.predictBulk(new Set<String>{ ' ' }).size());
    }

    @IsTest
    static void testPublishAlertIfNeededPublishesAtThreshold() {
        CortexTestUtils.useConfig(true, 0.7);
        ChurnPredictionService.ChurnPredictionResult result = new ChurnPredictionService.ChurnPredictionResult();
        result.customerId = 'TEST-Churn-Alert';
        result.compositeRisk = 0.7;
        result.riskBucket = '70-80%';
        result.recommendation = 'Monitor closely and re-engage with targeted offers.';

        Test.startTest();
        ChurnPredictionService.publishAlertIfNeeded(result);
        Integer publishes = Limits.getDmlStatements();
        Test.stopTest();

        System.assertEquals(1, publishes, 'A score equal to the threshold must raise an alert');
    }
}
