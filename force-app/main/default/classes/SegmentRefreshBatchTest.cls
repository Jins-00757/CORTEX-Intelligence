@IsTest
private class SegmentRefreshBatchTest {

    @IsTest
    static void batchAssignsRfmSegmentsToProfiles() {
        CortexTestUtils.insertProfiles(new List<String>{ 'B-SEG-HIGH', 'B-SEG-LOW' });
        List<CustomerDataEvents__b> events = new List<CustomerDataEvents__b>();
        for (Integer i = 0; i < 5; i++) {
            events.add(CortexTestUtils.event('B-SEG-HIGH', 'Purchase', i, 200));
        }
        events.add(CortexTestUtils.event('B-SEG-LOW', 'Purchase', 170, 10));
        CortexTestUtils.stubEvents(events);

        Test.startTest();
        Id jobId = SegmentRefreshBatch.run();
        Test.stopTest();

        System.assertNotEquals(null, jobId);
        Map<String, CustomerProfile__c> profiles = CortexTestUtils.profilesByExternalId();
        System.assertEquals('High', profiles.get('B-SEG-HIGH').CustomerSegment__c);
        System.assertEquals('Low', profiles.get('B-SEG-LOW').CustomerSegment__c);
    }

    @IsTest
    static void executeTracksSegmentedCustomers() {
        List<CustomerProfile__c> profiles = CortexTestUtils.insertProfiles(new List<String>{ 'B-SEG-1', 'B-SEG-2' });
        CortexTestUtils.stubEvents(null);
        SegmentRefreshBatch batch = new SegmentRefreshBatch();

        Test.startTest();
        batch.execute(null, profiles);
        Test.stopTest();

        System.assertEquals(2, batch.customersSegmented);
        System.assertEquals(0, batch.customersFailed);
    }

    @IsTest
    static void scopeSizeIsCapped() {
        CortexTestUtils.useConfig(true, 0.7);
        CortexConfigService.cachedConfig.BatchSize__c = 10000;
        System.assertEquals(SegmentRefreshBatch.MAX_SCOPE_SIZE, SegmentRefreshBatch.scopeSize());
    }
}
