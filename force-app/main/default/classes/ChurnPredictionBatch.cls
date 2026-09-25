/**
 * Nightly full re-score of churn risk for every CustomerProfile__c
 * (docs/ARCHITECTURE.md, Layer 3 "Nightly batch predictions").
 *
 * Complements the real-time CustomerDataEvent__e path: customers with no new
 * events still drift into risk as recency decays, and anything the real-time
 * path dropped (publish/enqueue failure) is healed here.
 *
 * A failing chunk is counted and logged rather than aborting the job, so one
 * bad chunk never prevents the rest of the population from being scored.
 */
public with sharing class ChurnPredictionBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    // Each chunk issues one Big Object query covering all its customers, so
    // scope size is capped well below CortexConfig BatchSize__c to keep the
    // chunk's event history under CustomerEventSelector.MAX_ROWS.
    public static final Integer MAX_SCOPE_SIZE = 200;

    @TestVisible
    private Integer customersScored = 0;
    @TestVisible
    private Integer customersFailed = 0;
    @TestVisible
    private Integer chunksFailed = 0;

    public static Id run() {
        return Database.executeBatch(new ChurnPredictionBatch(), scopeSize());
    }

    public static Integer scopeSize() {
        return Math.max(1, Math.min(CortexConfigService.getBatchSize(), MAX_SCOPE_SIZE));
    }

    public Database.QueryLocator start(Database.BatchableContext context) {
        return Database.getQueryLocator([
            SELECT ExternalCustomerId__c
            FROM CustomerProfile__c
            WHERE ExternalCustomerId__c != null
            ORDER BY Id
        ]);
    }

    public void execute(Database.BatchableContext context, List<CustomerProfile__c> scope) {
        // Re-checked per chunk so disabling predictions stops a running job.
        if (!CortexConfigService.isPredictionsEnabled()) {
            return;
        }

        Set<String> customerIds = new Set<String>();
        for (CustomerProfile__c profile : scope) {
            customerIds.add(profile.ExternalCustomerId__c);
        }

        try {
            ChurnPredictionService.predictBulk(customerIds);
            customersScored += customerIds.size();
        } catch (Exception e) {
            chunksFailed++;
            customersFailed += customerIds.size();
            System.debug(LoggingLevel.ERROR, 'ChurnPredictionBatch chunk failed (' + customerIds.size() +
                ' customers): ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'ChurnPredictionBatch ' + context.getJobId() + ' complete: ' +
            customersScored + ' customers scored, ' + customersFailed + ' failed across ' +
            chunksFailed + ' failed chunks.');
    }
}
