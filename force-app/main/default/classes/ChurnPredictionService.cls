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

        DateTime windowStart = System.now().addDays(-LOOKBACK_DAYS);
        List<CustomerDataEvents__b> events = [
            SELECT EventType__c, EventTimestamp__c, Amount__c
            FROM CustomerDataEvents__b
            WHERE CustomerId__c = :customerId AND EventTimestamp__c >= :windowStart
            LIMIT 5000
        ];

        ChurnPredictionResult result = calculate(customerId, events);
        persistSignal(result);
        updateCustomerProfile(result);
        publishAlertIfNeeded(result);
        return result;
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

    private static void persistSignal(ChurnPredictionResult result) {
        BigObjectWriter.insertImmediate(new ChurnSignals__b(
            CustomerId__c = result.customerId,
            SignalTimestamp__c = System.now(),
            RecencyRiskScore__c = result.recencyRisk,
            FrequencyRiskScore__c = result.frequencyRisk,
            MonetaryRiskScore__c = result.monetaryRisk,
            EngagementRiskScore__c = result.engagementRisk,
            SupportRiskScore__c = result.supportRisk,
            CompositeRiskScore__c = result.compositeRisk,
            RiskBucket__c = result.riskBucket
        ));
    }

    @TestVisible
    private static void updateCustomerProfile(ChurnPredictionResult result) {
        List<CustomerProfile__c> profiles = [
            SELECT Id, ChurnRiskScore__c
            FROM CustomerProfile__c
            WHERE ExternalCustomerId__c = :result.customerId
            LIMIT 1
        ];
        if (!profiles.isEmpty()) {
            profiles[0].ChurnRiskScore__c = result.compositeRisk;
            update profiles[0];
        }
    }

    @TestVisible
    private static void publishAlertIfNeeded(ChurnPredictionResult result) {
        Decimal threshold = CortexConfigService.getChurnRiskThreshold();
        if (result.compositeRisk < threshold) {
            return;
        }
        EventBus.publish(new ChurnAlertEvent__e(
            CustomerId__c = result.customerId,
            ChurnRiskScore__c = result.compositeRisk,
            RiskBucket__c = result.riskBucket,
            AlertTimestamp__c = System.now(),
            RecommendedAction__c = result.recommendation
        ));
    }
}
