// DataIngestionService.ingest() only calls IngestionResult.duplicateEvent()
// after a Big Object dedupe query finds a match, and that query can't be
// exercised in Apex tests (see DataIngestionServiceTest's comment on
// matchExistingKeys), so the factory methods are verified directly here.
@IsTest
private class IngestionResultTest {

    @IsTest
    static void testSuccessFactory() {
        IngestionResult result = IngestionResult.success('evt-1');

        System.assertEquals(true, result.isSuccess);
        System.assertEquals(false, result.isDuplicate);
        System.assertEquals('evt-1', result.eventId);
        System.assertEquals(null, result.errorMessage);
    }

    @IsTest
    static void testDuplicateEventFactory() {
        IngestionResult result = IngestionResult.duplicateEvent('evt-2');

        System.assertEquals(false, result.isSuccess);
        System.assertEquals(true, result.isDuplicate);
        System.assertEquals('evt-2', result.eventId);
    }

    @IsTest
    static void testFailureFactory() {
        IngestionResult result = IngestionResult.failure('something went wrong');

        System.assertEquals(false, result.isSuccess);
        System.assertEquals(false, result.isDuplicate);
        System.assertEquals('something went wrong', result.errorMessage);
    }
}
