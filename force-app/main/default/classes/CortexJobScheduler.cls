/**
 * Schedules and launches the Cortex batch jobs.
 *
 * A single thin Schedulable dispatches to the batch classes, so the batch
 * classes themselves are never locked against deployment by a pending
 * scheduled job - only this small, rarely-changing class is.
 *
 * Usage (anonymous Apex):
 *   CortexJobScheduler.scheduleAll();   // idempotent: replaces existing Cortex jobs
 *   CortexJobScheduler.unscheduleAll();
 *   CortexJobScheduler.launch(CortexJobScheduler.Job.CHURN_PREDICTION); // run now
 */
public with sharing class CortexJobScheduler implements Schedulable {

    public enum Job { CHURN_PREDICTION, SEGMENT_REFRESH }

    public static final String CHURN_JOB_NAME = 'Cortex - Nightly Churn Prediction';
    public static final String SEGMENT_JOB_NAME = 'Cortex - Weekly Segment Refresh';

    // Seconds Minutes Hours Day-of-month Month Day-of-week (org time zone).
    public static final String CHURN_CRON = '0 0 2 * * ?';
    public static final String SEGMENT_CRON = '0 0 3 ? * SUN';

    private final Job jobType;

    public CortexJobScheduler(Job jobType) {
        if (jobType == null) {
            throw new CortexServiceException('A job type is required.');
        }
        this.jobType = jobType;
    }

    public void execute(SchedulableContext context) {
        launch(jobType);
    }

    public static Id launch(Job jobType) {
        switch on jobType {
            when CHURN_PREDICTION {
                if (!CortexConfigService.isPredictionsEnabled()) {
                    return null;
                }
                return ChurnPredictionBatch.run();
            }
            when SEGMENT_REFRESH {
                return SegmentRefreshBatch.run();
            }
            when else {
                throw new CortexServiceException('Unsupported job type: ' + jobType);
            }
        }
    }

    /**
     * Idempotently (re)schedules every Cortex job on its default cadence.
     * Returns the CronTrigger Id for each job name.
     */
    public static Map<String, Id> scheduleAll() {
        unscheduleAll();
        return new Map<String, Id>{
            CHURN_JOB_NAME => System.schedule(CHURN_JOB_NAME, CHURN_CRON, new CortexJobScheduler(Job.CHURN_PREDICTION)),
            SEGMENT_JOB_NAME => System.schedule(SEGMENT_JOB_NAME, SEGMENT_CRON, new CortexJobScheduler(Job.SEGMENT_REFRESH))
        };
    }

    public static Integer unscheduleAll() {
        List<CronTrigger> existing = [
            SELECT Id
            FROM CronTrigger
            WHERE CronJobDetail.Name IN :new Set<String>{ CHURN_JOB_NAME, SEGMENT_JOB_NAME }
        ];
        for (CronTrigger cronTrigger : existing) {
            System.abortJob(cronTrigger.Id);
        }
        return existing.size();
    }
}
