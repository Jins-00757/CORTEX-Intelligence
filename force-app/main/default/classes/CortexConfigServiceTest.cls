@IsTest
private class CortexConfigServiceTest {

    @IsTest
    static void testGetConfigReturnsDefaultRecord() {
        Test.startTest();
        CortexConfig__mdt config = CortexConfigService.getConfig();
        Test.stopTest();

        System.assertNotEquals(null, config);
        System.assertEquals('Default_Config', config.DeveloperName);
    }

    @IsTest
    static void testGetChurnRiskThresholdMatchesDefaultRecord() {
        Test.startTest();
        Decimal threshold = CortexConfigService.getChurnRiskThreshold();
        Test.stopTest();

        System.assertEquals(0.7, threshold);
    }

    @IsTest
    static void testGetBatchSizeMatchesDefaultRecord() {
        Test.startTest();
        Integer batchSize = CortexConfigService.getBatchSize();
        Test.stopTest();

        System.assertEquals(10000, batchSize);
    }

    @IsTest
    static void testIsPredictionsEnabledMatchesDefaultRecord() {
        Test.startTest();
        Boolean enabled = CortexConfigService.isPredictionsEnabled();
        Test.stopTest();

        System.assertEquals(true, enabled);
    }
}
