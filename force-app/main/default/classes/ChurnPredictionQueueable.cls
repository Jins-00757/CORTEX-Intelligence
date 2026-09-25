/**
 * Asynchronously re-scores churn risk for a set of customers, in chunks.
 *
 * Enqueued by the CustomerDataEvent__e subscriber so real-time ingestion never
 * waits on scoring. Each execution scores at most CHUNK_SIZE customers (one
 * Big Object query per transaction, bounded by CustomerEventSelector.MAX_ROWS)
 * and chains a follow-up job for the remainder.
 *
 * Implements Database.AllowsCallouts because Big Object SOQL is executed as
 * a callout under the hood (see CustomerEventSelector).
 */
public with sharing class ChurnPredictionQueueable implements Queueable, Database.AllowsCallouts {

    @TestVisible
    private static final Integer CHUNK_SIZE = 100;

    // Apex tests cannot chain Queueables, so in test context the remainder
    // is captured here for assertions instead of being enqueued.
    @TestVisible
    private static List<String> remainderCapturedInTest;

    private final List<String> customerIds;

    public ChurnPredictionQueueable(Set<String> customerIds) {
        this.customerIds = customerIds == null ? new List<String>() : new List<String>(customerIds);
    }

    public void execute(QueueableContext context) {
        if (customerIds.isEmpty() || !CortexConfigService.isPredictionsEnabled()) {
            return;
        }

        Set<String> currentChunk = new Set<String>();
        Set<String> remainder = new Set<String>();
        for (Integer i = 0; i < customerIds.size(); i++) {
            if (i < CHUNK_SIZE) {
                currentChunk.add(customerIds[i]);
            } else {
                remainder.add(customerIds[i]);
            }
        }

        // Enqueue before scoring: if scoring throws, the whole transaction
        // (including this enqueue) rolls back and the remainder is picked up
        // by the nightly ChurnPredictionBatch rather than silently lost mid-way.
        if (!remainder.isEmpty()) {
            if (Test.isRunningTest()) {
                remainderCapturedInTest = new List<String>(remainder);
            } else {
                System.enqueueJob(new ChurnPredictionQueueable(remainder));
            }
        }

        ChurnPredictionService.predictBulk(currentChunk);
    }
}
