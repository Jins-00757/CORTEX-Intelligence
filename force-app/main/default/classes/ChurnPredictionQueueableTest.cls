@IsTest
private class ChurnPredictionQueueableTest {

    @IsTest
    static void scoresFirstChunkAndDefersRemainder() {
        Set<String> customerIds = new Set<String>();
        for (Integer i = 0; i < ChurnPredictionQueueable.CHUNK_SIZE + 25; i++) {
            customerIds.add('Q-CUST-' + i);
        }
        CortexTestUtils.insertProfiles(new List<String>{ 'Q-CUST-0' });
        CortexTestUtils.stubEvents(null);

        Test.startTest();
        System.enqueueJob(new ChurnPredictionQueueable(customerIds));
        Test.stopTest();

        System.assertEquals(25, ChurnPredictionQueueable.remainderCapturedInTest.size());
        System.assertEquals(0.85, CortexTestUtils.profilesByExternalId().get('Q-CUST-0').ChurnRiskScore__c);
    }

    @IsTest
    static void singleChunkDoesNotChain() {
        CortexTestUtils.insertProfiles(new List<String>{ 'Q-CUST-A' });
        CortexTestUtils.stubEvents(null);

        Test.startTest();
        System.enqueueJob(new ChurnPredictionQueueable(new Set<String>{ 'Q-CUST-A' }));
        Test.stopTest();

        System.assertEquals(null, ChurnPredictionQueueable.remainderCapturedInTest);
        System.assertEquals(0.85, CortexTestUtils.profilesByExternalId().get('Q-CUST-A').ChurnRiskScore__c);
    }

    @IsTest
    static void noOpWhenDisabledOrEmpty() {
        CortexTestUtils.insertProfiles(new List<String>{ 'Q-CUST-B' });
        CortexTestUtils.disablePredictions();

        Test.startTest();
        new ChurnPredictionQueueable(new Set<String>{ 'Q-CUST-B' }).execute(null);
        new ChurnPredictionQueueable(null).execute(null);
        Test.stopTest();

        System.assertEquals(0, CortexTestUtils.profilesByExternalId().get('Q-CUST-B').ChurnRiskScore__c);
    }
}
