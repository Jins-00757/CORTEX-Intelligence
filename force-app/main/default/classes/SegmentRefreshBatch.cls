/**
 * Weekly RFM segmentation refresh for every CustomerProfile__c
 * (docs/ARCHITECTURE.md, Layer 4 "Weekly segmentation refresh").
 *
 * Note: SegmentBuilderService scores RFM relative to the customers passed in
 * a single call, so here High/Mid/Low are relative within each chunk. With a
 * large, ORDER BY Id (effectively arbitrary) chunk the distribution is a
 * reasonable sample of the population; a population-wide two-pass normalisation
 * is a candidate future enhancement.
 */
public with sharing class SegmentRefreshBatch implements Database.Batchable<SObject>, Database.AllowsCallouts, Database.Stateful {

    public static final Integer MAX_SCOPE_SIZE = 200;

    @TestVisible
    private Integer customersSegmented = 0;
    @TestVisible
    private Integer customersFailed = 0;
    @TestVisible
    private Integer chunksFailed = 0;

    public static Id run() {
        return Database.executeBatch(new SegmentRefreshBatch(), scopeSize());
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
        Set<String> customerIds = new Set<String>();
        for (CustomerProfile__c profile : scope) {
            customerIds.add(profile.ExternalCustomerId__c);
        }

        try {
            SegmentBuilderService.classifyAndUpdate(customerIds);
            customersSegmented += customerIds.size();
        } catch (Exception e) {
            chunksFailed++;
            customersFailed += customerIds.size();
            System.debug(LoggingLevel.ERROR, 'SegmentRefreshBatch chunk failed (' + customerIds.size() +
                ' customers): ' + e.getTypeName() + ': ' + e.getMessage());
        }
    }

    public void finish(Database.BatchableContext context) {
        System.debug(LoggingLevel.INFO, 'SegmentRefreshBatch ' + context.getJobId() + ' complete: ' +
            customersSegmented + ' customers segmented, ' + customersFailed + ' failed across ' +
            chunksFailed + ' failed chunks.');
    }
}
