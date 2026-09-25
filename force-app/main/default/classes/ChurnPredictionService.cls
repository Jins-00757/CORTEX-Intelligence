/**
 * Computes composite churn risk for a customer from their CustomerDataEvents__b
 * history, persists the result to ChurnSignals__b, updates the corresponding
 * CustomerProfile__c.ChurnRiskScore__c, and publishes a ChurnAlertEvent__e
 * when the score meets or exceeds the configured threshold (CortexConfig__mdt).
 *
 * Weighting matches docs/ARCHITECTURE.md Layer 3: Recency 30%, Frequency 20%,
 * Monetary 15%, Engagement 20%, Support 15%.
 */
public with sharing class ChurnPredictionService {

    private static final Decimal RECENCY_WEIGHT = 0.30;
    private static final Decimal FREQUENCY_WEIGHT = 0.20;
    private static final Decimal MONETARY_WEIGHT = 0.15;
    private static final Decimal ENGAGEMENT_WEIGHT = 0.20;
    private static final Decimal SUPPORT_WEIGHT = 0.15;

    private static final Integer LOOKBACK_DAYS = 180;
    private static final Integer RECENCY_MAX_DAYS = 90;
    private static final Integer TARGET_PURCHASE_COUNT = 4;
    private static final Decimal TARGET_ORDER_VALUE = 100;
    private static final Integer TARGET_ENGAGEMENT_COUNT = 10;
    private static final Integer SUPPORT_TICKET_CEILING = 5;

    private static final String EVENT_TYPE_PURCHASE = 'Purchase';
    private static final String EVENT_TYPE_SUPPORT_TICKET = 'SupportTicket';

    public class ChurnPredictionResult {
        public String customerId;
        public Decimal recencyRisk;
        public Decimal frequencyRisk;
        public Decimal monetaryRisk;
        public Decimal engagementRisk;
        public Decimal supportRisk;
        public Decimal compositeRisk;
        public String riskBucket;
        public String recommendation;
    }

    public static ChurnPredictionResult predict(String customerId) {
        if (String.isBlank(customerId)) {
            throw new CortexServiceException('CustomerId is required to compute a churn prediction.');
        }
        return predictBulk(new Set<String>{ customerId })[0];
    }

    /**
     * Bulk-safe variant used by the REST API, the CustomerDataEvent__e
     * subscriber and the nightly batch. All reads happen before any DML:
     * Big Object SOQL is executed as a callout, and a callout after
     * uncommitted DML in the same transaction is rejected by the platform.
     */
    public static List<ChurnPredictionResult> predictBulk(Set<String> customerIds) {
        Set<String> scopedIds = new Set<String>();
        if (customerIds != null) {
            for (String customerId : customerIds) {
                if (String.isNotBlank(customerId)) {
                    scopedIds.add(customerId);
                }
            }
        }
        if (scopedIds.isEmpty()) {
            return new List<ChurnPredictionResult>();
        }

        DateTime windowStart = System.now().addDays(-LOOKBACK_DAYS);
        Map<String, List<CustomerDataEvents__b>> eventsByCustomer = new Map<String, List<CustomerDataEvents__b>>();
        for (String customerId : scopedIds) {
            eventsByCustomer.put(customerId, new List<CustomerDataEvents__b>());
        }
        for (CustomerDataEvents__b event : CustomerEventSelector.selectSince(scopedIds, windowStart)) {
            List<CustomerDataEvents__b> bucket = eventsByCustomer.get(event.CustomerId__c);
            if (bucket != null) {
                bucket.add(event);
            }
        }

        List<ChurnPredictionResult> results = new List<ChurnPredictionResult>();
        for (String customerId : scopedIds) {
            results.add(calculate(customerId, eventsByCustomer.get(customerId)));
        }

        persistSignals(results);
        updateCustomerProfiles(results);
        publishAlertsIfNeeded(results);
        return results;
    }

    @TestVisible
    private static ChurnPredictionResult calculate(String customerId, List<CustomerDataEvents__b> events) {
        Integer purchaseCount = 0;
        Integer engagementCount = 0;
        Integer supportTicketCount = 0;
        Decimal totalPurchaseAmount = 0;
        DateTime mostRecentPurchase = null;

        for (CustomerDataEvents__b event : events) {
            if (event.EventType__c == EVENT_TYPE_PURCHASE) {
                purchaseCount++;
                totalPurchaseAmount += (event.Amount__c != null ? event.Amount__c : 0);
                if (mostRecentPurchase == null || event.EventTimestamp__c > mostRecentPurchase) {
                    mostRecentPurchase = event.EventTimestamp__c;
                }
            } else if (event.EventType__c == EVENT_TYPE_SUPPORT_TICKET) {
                supportTicketCount++;
            } else {
                engagementCount++;
            }
        }

        Decimal recencyRisk = calculateRecencyRisk(mostRecentPurchase);
        Decimal frequencyRisk = calculateBoundedRisk(purchaseCount, TARGET_PURCHASE_COUNT, true);
        Decimal averageOrderValue = purchaseCount > 0 ? totalPurchaseAmount / purchaseCount : 0;
        Decimal monetaryRisk = calculateBoundedRisk(averageOrderValue, TARGET_ORDER_VALUE, true);
        Decimal engagementRisk = calculateBoundedRisk(engagementCount, TARGET_ENGAGEMENT_COUNT, true);
        Decimal supportRisk = calculateBoundedRisk(supportTicketCount, SUPPORT_TICKET_CEILING, false);

        Decimal composite = (recencyRisk * RECENCY_WEIGHT)
            + (frequencyRisk * FREQUENCY_WEIGHT)
            + (monetaryRisk * MONETARY_WEIGHT)
            + (engagementRisk * ENGAGEMENT_WEIGHT)
            + (supportRisk * SUPPORT_WEIGHT);
        composite = composite.setScale(4, RoundingMode.HALF_UP);

        ChurnPredictionResult result = new ChurnPredictionResult();
        result.customerId = customerId;
        result.recencyRisk = recencyRisk.setScale(4, RoundingMode.HALF_UP);
        result.frequencyRisk = frequencyRisk.setScale(4, RoundingMode.HALF_UP);
        result.monetaryRisk = monetaryRisk.setScale(4, RoundingMode.HALF_UP);
        result.engagementRisk = engagementRisk.setScale(4, RoundingMode.HALF_UP);
        result.supportRisk = supportRisk.setScale(4, RoundingMode.HALF_UP);
        result.compositeRisk = composite;
        result.riskBucket = bucketFor(composite);
        result.recommendation = recommendationFor(result.riskBucket);
        return result;
    }

    private static Decimal calculateRecencyRisk(DateTime mostRecentPurchase) {
        if (mostRecentPurchase == null) {
            return 1;
        }
        Long daysSince = (System.now().getTime() - mostRecentPurchase.getTime()) / (1000 * 60 * 60 * 24);
        return minOne(Decimal.valueOf(daysSince) / RECENCY_MAX_DAYS);
    }

    /**
     * Maps a raw metric onto a 0-1 risk score against a target baseline.
     * inverse = true means higher raw values reduce risk (e.g. more purchases
     * is better); inverse = false means higher raw values increase risk
     * (e.g. more support tickets is worse).
     */
    private static Decimal calculateBoundedRisk(Decimal rawValue, Decimal target, Boolean inverse) {
        Decimal ratio = minOne(rawValue / target);
        return inverse ? (1 - ratio) : ratio;
    }

    private static Decimal minOne(Decimal value) {
        if (value > 1) {
            return 1;
        }
        if (value < 0) {
            return 0;
        }
        return value;
    }

    private static String bucketFor(Decimal composite) {
        if (composite >= 0.90) {
            return '90-100%';
        }
        if (composite >= 0.80) {
            return '80-90%';
        }
        if (composite >= 0.70) {
            return '70-80%';
        }
        return 'Not At Risk';
    }

    private static String recommendationFor(String riskBucket) {
        if (riskBucket == '90-100%') {
            return 'Immediate retention outreach recommended.';
        }
        if (riskBucket == '80-90%') {
            return 'Proactive account manager engagement recommended.';
        }
        if (riskBucket == '70-80%') {
            return 'Monitor closely and re-engage with targeted offers.';
        }
        return 'No action required.';
    }

    private static void persistSignals(List<ChurnPredictionResult> results) {
        DateTime signalTimestamp = System.now();
        List<ChurnSignals__b> signals = new List<ChurnSignals__b>();
        for (ChurnPredictionResult result : results) {
            signals.add(new ChurnSignals__b(
                CustomerId__c = result.customerId,
                SignalTimestamp__c = signalTimestamp,
                RecencyRiskScore__c = result.recencyRisk,
                FrequencyRiskScore__c = result.frequencyRisk,
                MonetaryRiskScore__c = result.monetaryRisk,
                EngagementRiskScore__c = result.engagementRisk,
                SupportRiskScore__c = result.supportRisk,
                CompositeRiskScore__c = result.compositeRisk,
                RiskBucket__c = result.riskBucket
            ));
        }
        List<BigObjectWriter.WriteResult> writeResults = BigObjectWriter.insertImmediate(signals);
        for (Integer i = 0; i < writeResults.size(); i++) {
            if (!writeResults[i].isSuccess) {
                System.debug(LoggingLevel.ERROR, 'ChurnSignals__b write failed for ' +
                    results[i].customerId + ': ' + writeResults[i].errorMessage);
            }
        }
    }

    @TestVisible
    private static void updateCustomerProfile(ChurnPredictionResult result) {
        updateCustomerProfiles(new List<ChurnPredictionResult>{ result });
    }

    private static void updateCustomerProfiles(List<ChurnPredictionResult> results) {
        Map<String, Decimal> scoreByCustomerId = new Map<String, Decimal>();
        for (ChurnPredictionResult result : results) {
            scoreByCustomerId.put(result.customerId, result.compositeRisk);
        }

        List<CustomerProfile__c> profilesToUpdate = new List<CustomerProfile__c>();
        for (CustomerProfile__c profile : [
            SELECT Id, ExternalCustomerId__c, ChurnRiskScore__c
            FROM CustomerProfile__c
            WHERE ExternalCustomerId__c IN :scoreByCustomerId.keySet()
        ]) {
            Decimal newScore = scoreByCustomerId.get(profile.ExternalCustomerId__c);
            if (newScore != profile.ChurnRiskScore__c) {
                profile.ChurnRiskScore__c = newScore;
                profilesToUpdate.add(profile);
            }
        }
        if (!profilesToUpdate.isEmpty()) {
            update profilesToUpdate;
        }
    }

    @TestVisible
    private static void publishAlertIfNeeded(ChurnPredictionResult result) {
        publishAlertsIfNeeded(new List<ChurnPredictionResult>{ result });
    }

    private static void publishAlertsIfNeeded(List<ChurnPredictionResult> results) {
        Decimal threshold = CortexConfigService.getChurnRiskThreshold();
        DateTime alertTimestamp = System.now();
        List<ChurnAlertEvent__e> alerts = new List<ChurnAlertEvent__e>();
        for (ChurnPredictionResult result : results) {
            if (result.compositeRisk >= threshold) {
                alerts.add(new ChurnAlertEvent__e(
                    CustomerId__c = result.customerId,
                    ChurnRiskScore__c = result.compositeRisk,
                    RiskBucket__c = result.riskBucket,
                    AlertTimestamp__c = alertTimestamp,
                    RecommendedAction__c = result.recommendation
                ));
            }
        }
        if (alerts.isEmpty()) {
            return;
        }
        List<Database.SaveResult> publishResults = EventBus.publish(alerts);
        for (Integer i = 0; i < publishResults.size(); i++) {
            if (!publishResults[i].isSuccess()) {
                System.debug(LoggingLevel.ERROR, 'ChurnAlertEvent__e publish failed for ' +
                    alerts[i].CustomerId__c + ': ' + publishResults[i].getErrors());
            }
        }
    }
}
