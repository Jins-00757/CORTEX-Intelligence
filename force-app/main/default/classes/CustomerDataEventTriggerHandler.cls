/**
 * Subscriber logic for CustomerDataEvent__e (published by DataIngestionService
 * after events are stored). Collapses each delivered batch to its distinct
 * customers and hands them to ChurnPredictionQueueable, keeping the trigger
 * itself fast: platform event triggers cannot make callouts, and Big Object
 * SOQL is a callout, so scoring must run asynchronously anyway.
 */
public with sharing class CustomerDataEventTriggerHandler {

    // EventBus redelivers the whole batch on RetryableException; beyond this
    // the batch is dropped (logged) and the nightly batch job re-scores
    // everyone, so a transient failure never loses a customer permanently.
    @TestVisible
    private static final Integer MAX_RETRIES = 3;

    public static void afterInsert(List<CustomerDataEvent__e> events) {
        if (events == null || events.isEmpty() || !CortexConfigService.isPredictionsEnabled()) {
            return;
        }

        Set<String> customerIds = new Set<String>();
        for (CustomerDataEvent__e event : events) {
            if (String.isNotBlank(event.CustomerId__c)) {
                customerIds.add(event.CustomerId__c);
            }
        }
        if (customerIds.isEmpty()) {
            return;
        }

        try {
            System.enqueueJob(new ChurnPredictionQueueable(customerIds));
        } catch (Exception e) {
            Integer retries = EventBus.TriggerContext.currentContext().retries;
            if (retries < MAX_RETRIES) {
                throw new EventBus.RetryableException(
                    'Unable to enqueue churn re-scoring (attempt ' + (retries + 1) + '): ' + e.getMessage()
                );
            }
            System.debug(LoggingLevel.ERROR, 'Dropping churn re-scoring for ' + customerIds.size() +
                ' customers after ' + retries + ' retries: ' + e.getMessage());
        }
    }
}
