@IsTest
private class CustomerDataEventTriggerHandlerTest {

    private static CustomerDataEvent__e notification(String customerId, String eventId) {
        return new CustomerDataEvent__e(
            CustomerId__c = customerId,
            EventId__c = eventId,
            EventType__c = 'Login',
            EventTimestamp__c = System.now()
        );
    }

    private static Integer queuedScoringJobs() {
        return [
            SELECT COUNT()
            FROM AsyncApexJob
            WHERE JobType = 'Queueable' AND ApexClass.Name = 'ChurnPredictionQueueable'
        ];
    }

    @IsTest
    static void deliveredEventsRescoreEachDistinctCustomerOnce() {
        CortexTestUtils.insertProfiles(new List<String>{ 'PE-CUST-1', 'PE-CUST-2' });
        CortexTestUtils.stubEvents(CortexTestUtils.healthyHistory('PE-CUST-2'));

        Test.startTest();
        EventBus.publish(new List<CustomerDataEvent__e>{
            notification('PE-CUST-1', 'e1'),
            notification('PE-CUST-1', 'e2'),
            notification('PE-CUST-2', 'e3')
        });
        Test.getEventBus().deliver();
        System.assertEquals(1, queuedScoringJobs(), 'One queueable should cover the whole delivered batch');
        Test.stopTest();

        Map<String, CustomerProfile__c> profiles = CortexTestUtils.profilesByExternalId();
        System.assertEquals(0.85, profiles.get('PE-CUST-1').ChurnRiskScore__c);
        System.assertEquals(0, profiles.get('PE-CUST-2').ChurnRiskScore__c);
    }

    @IsTest
    static void predictionsDisabledSkipsRescoring() {
        CortexTestUtils.disablePredictions();

        Test.startTest();
        CustomerDataEventTriggerHandler.afterInsert(new List<CustomerDataEvent__e>{ notification('PE-CUST-1', 'e1') });
        Test.stopTest();

        System.assertEquals(0, queuedScoringJobs());
    }

    @IsTest
    static void emptyOrCustomerlessBatchesAreIgnored() {
        Test.startTest();
        CustomerDataEventTriggerHandler.afterInsert(new List<CustomerDataEvent__e>());
        CustomerDataEventTriggerHandler.afterInsert(null);
        CustomerDataEventTriggerHandler.afterInsert(new List<CustomerDataEvent__e>{ notification(' ', 'e1') });
        Test.stopTest();

        System.assertEquals(0, queuedScoringJobs());
    }
}
