@IsTest
private class CortexJobSchedulerTest {

    private static Map<String, String> scheduledCronByName() {
        Map<String, String> result = new Map<String, String>();
        for (CronTrigger cronTrigger : [
            SELECT CronExpression, CronJobDetail.Name
            FROM CronTrigger
            WHERE CronJobDetail.Name IN :new Set<String>{ CortexJobScheduler.CHURN_JOB_NAME, CortexJobScheduler.SEGMENT_JOB_NAME }
        ]) {
            result.put(cronTrigger.CronJobDetail.Name, cronTrigger.CronExpression);
        }
        return result;
    }

    @IsTest
    static void scheduleAllIsIdempotent() {
        Test.startTest();
        CortexJobScheduler.scheduleAll();
        Map<String, Id> second = CortexJobScheduler.scheduleAll();
        Test.stopTest();

        System.assertEquals(2, second.size());
        Map<String, String> scheduled = scheduledCronByName();
        System.assertEquals(2, scheduled.size(), 'Re-scheduling must replace, not duplicate, existing jobs');
        System.assertEquals(CortexJobScheduler.CHURN_CRON, scheduled.get(CortexJobScheduler.CHURN_JOB_NAME));
        System.assertEquals(CortexJobScheduler.SEGMENT_CRON, scheduled.get(CortexJobScheduler.SEGMENT_JOB_NAME));
    }

    @IsTest
    static void unscheduleAllRemovesCortexJobs() {
        CortexJobScheduler.scheduleAll();

        Test.startTest();
        Integer removed = CortexJobScheduler.unscheduleAll();
        Test.stopTest();

        System.assertEquals(2, removed);
        System.assertEquals(0, scheduledCronByName().size());
    }

    @IsTest
    static void scheduledExecutionLaunchesChurnBatch() {
        CortexTestUtils.stubEvents(null);

        Test.startTest();
        new CortexJobScheduler(CortexJobScheduler.Job.CHURN_PREDICTION).execute(null);
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'ChurnPredictionBatch'
        ]);
    }

    @IsTest
    static void scheduledExecutionLaunchesSegmentBatch() {
        CortexTestUtils.stubEvents(null);

        Test.startTest();
        new CortexJobScheduler(CortexJobScheduler.Job.SEGMENT_REFRESH).execute(null);
        Test.stopTest();

        System.assertEquals(1, [
            SELECT COUNT() FROM AsyncApexJob WHERE JobType = 'BatchApex' AND ApexClass.Name = 'SegmentRefreshBatch'
        ]);
    }

    @IsTest
    static void churnLaunchIsSkippedWhenPredictionsDisabled() {
        CortexTestUtils.disablePredictions();

        Test.startTest();
        Id jobId = CortexJobScheduler.launch(CortexJobScheduler.Job.CHURN_PREDICTION);
        Test.stopTest();

        System.assertEquals(null, jobId);
    }

    @IsTest
    static void constructorRequiresJobType() {
        try {
            new CortexJobScheduler(null);
            System.assert(false, 'Expected a CortexServiceException for a null job type');
        } catch (CortexServiceException e) {
            System.assert(e.getMessage().contains('job type'));
        }
    }
}
