@IsTest
private class ChurnPredictionBatchTest {

    @IsTest
    static void batchScoresEveryProfile() {
        CortexTestUtils.insertProfiles(new List<String>{ 'B-CHURN-1', 'B-CHURN-2', 'B-CHURN-3' });
        CortexTestUtils.stubEvents(CortexTestUtils.healthyHistory('B-CHURN-2'));

        Test.startTest();
        Id jobId = ChurnPredictionBatch.run();
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Map<String, CustomerProfile__c> profiles = CortexTestUtils.profilesByExternalId();
        System.assertEquals(0.85, profiles.get('B-CHURN-1').ChurnRiskScore__c);
        System.assertEquals(0, profiles.get('B-CHURN-2').ChurnRiskScore__c);
        System.assertEquals(0.85, profiles.get('B-CHURN-3').ChurnRiskScore__c);
        System.assertEquals('Completed', [SELECT Status FROM AsyncApexJob WHERE Id = :jobId].Status);
    }

    @IsTest
    static void executeTracksScoredCustomers() {
        List<CustomerProfile__c> profiles = CortexTestUtils.insertProfiles(new List<String>{ 'B-CHURN-4', 'B-CHURN-5' });
        CortexTestUtils.stubEvents(null);
        ChurnPredictionBatch batch = new ChurnPredictionBatch();

        Test.startTest();
        batch.execute(null, profiles);
        Test.stopTest();

        System.assertEquals(2, batch.customersScored);
        System.assertEquals(0, batch.customersFailed);
    }

    @IsTest
    static void executeIsNoOpWhenPredictionsDisabled() {
        List<CustomerProfile__c> profiles = CortexTestUtils.insertProfiles(new List<String>{ 'B-CHURN-6' });
        CortexTestUtils.disablePredictions();
        ChurnPredictionBatch batch = new ChurnPredictionBatch();

        Test.startTest();
        batch.execute(null, profiles);
        Test.stopTest();

        System.assertEquals(0, batch.customersScored);
        System.assertEquals(0, CortexTestUtils.profilesByExternalId().get('B-CHURN-6').ChurnRiskScore__c);
    }

    @IsTest
    static void scopeSizeIsCappedForBigObjectQueryLimits() {
        CortexTestUtils.useConfig(true, 0.7);
        CortexConfigService.cachedConfig.BatchSize__c = 10000;
        System.assertEquals(ChurnPredictionBatch.MAX_SCOPE_SIZE, ChurnPredictionBatch.scopeSize());

        CortexConfigService.cachedConfig.BatchSize__c = 50;
        System.assertEquals(50, ChurnPredictionBatch.scopeSize());

        CortexConfigService.cachedConfig.BatchSize__c = 0;
        System.assertEquals(1, ChurnPredictionBatch.scopeSize());
    }
}
