/**
 * RFM-style customer segmentation, lookalike-audience matching, and a
 * whitelist-guarded dynamic segment query builder (see querySegment for the
 * SOQL-injection safeguard described in docs/ARCHITECTURE.md's Security Model).
 */
public with sharing class SegmentBuilderService {

    private static final String EVENT_TYPE_PURCHASE = 'Purchase';
    private static final Integer LOOKBACK_DAYS = 180;

    private static final Set<String> ALLOWED_FILTER_FIELDS = new Set<String>{
        'CustomerSegment__c', 'ChurnRiskScore__c', 'LifetimeValue__c', 'ExternalCustomerId__c'
    };

    private static final Map<String, String> ALLOWED_OPERATORS = new Map<String, String>{
        '=' => '=', '!=' => '!=', '>' => '>', '<' => '<', '>=' => '>=', '<=' => '<='
    };

    public class RfmScore {
        public String customerId;
        public Integer recency;
        public Integer frequency;
        public Decimal monetary;
        public String segment;
    }

    /**
     * Classifies each customer into a High/Mid/Low RFM segment (relative to
     * the other customers in this batch) and persists the result onto
     * CustomerProfile__c.CustomerSegment__c.
     */
    public static List<RfmScore> classifyAndUpdate(Set<String> customerIds) {
        if (customerIds == null || customerIds.isEmpty()) {
            return new List<RfmScore>();
        }

        // Big Object SOQL can only filter on indexed fields (CustomerId__c,
        // EventTimestamp__c), so the EventType__c == Purchase filter is
        // applied here in Apex rather than in the WHERE clause.
        DateTime windowStart = System.now().addDays(-LOOKBACK_DAYS);
        List<CustomerDataEvents__b> events = [
            SELECT CustomerId__c, EventType__c, EventTimestamp__c, Amount__c
            FROM CustomerDataEvents__b
            WHERE CustomerId__c IN :customerIds AND EventTimestamp__c >= :windowStart
            LIMIT 50000
        ];

        List<RfmScore> scores = classifyFromEvents(customerIds, events);
        updateProfiles(scores);
        return scores;
    }

    /**
     * Pure RFM scoring logic, separated from the SOQL query above so it can
     * be unit tested against in-memory event data without needing real
     * CustomerDataEvents__b records to exist in the org.
     */
    @TestVisible
    private static List<RfmScore> classifyFromEvents(Set<String> customerIds, List<CustomerDataEvents__b> events) {
        Map<String, List<CustomerDataEvents__b>> purchasesByCustomer = new Map<String, List<CustomerDataEvents__b>>();
        for (String customerId : customerIds) {
            purchasesByCustomer.put(customerId, new List<CustomerDataEvents__b>());
        }
        for (CustomerDataEvents__b event : events) {
            if (event.EventType__c == EVENT_TYPE_PURCHASE) {
                purchasesByCustomer.get(event.CustomerId__c).add(event);
            }
        }

        Map<String, RfmScore> scoresByCustomer = new Map<String, RfmScore>();
        Decimal maxMonetary = 0;
        Integer maxFrequency = 0;
        Integer maxRecency = 0;

        for (String customerId : customerIds) {
            List<CustomerDataEvents__b> customerPurchases = purchasesByCustomer.get(customerId);
            RfmScore score = new RfmScore();
            score.customerId = customerId;
            score.frequency = customerPurchases.size();

            Decimal totalAmount = 0;
            DateTime mostRecent = null;
            for (CustomerDataEvents__b purchase : customerPurchases) {
                totalAmount += (purchase.Amount__c != null ? purchase.Amount__c : 0);
                if (mostRecent == null || purchase.EventTimestamp__c > mostRecent) {
                    mostRecent = purchase.EventTimestamp__c;
                }
            }
            score.monetary = totalAmount;
            score.recency = mostRecent == null
                ? LOOKBACK_DAYS
                : Integer.valueOf((System.now().getTime() - mostRecent.getTime()) / (1000 * 60 * 60 * 24));

            if (score.monetary > maxMonetary) {
                maxMonetary = score.monetary;
            }
            if (score.frequency > maxFrequency) {
                maxFrequency = score.frequency;
            }
            if (score.recency > maxRecency) {
                maxRecency = score.recency;
            }

            scoresByCustomer.put(customerId, score);
        }

        for (RfmScore score : scoresByCustomer.values()) {
            Decimal recencyComponent = maxRecency == 0 ? 1 : (1 - (Decimal.valueOf(score.recency) / maxRecency));
            Decimal frequencyComponent = maxFrequency == 0 ? 0 : (Decimal.valueOf(score.frequency) / maxFrequency);
            Decimal monetaryComponent = maxMonetary == 0 ? 0 : (score.monetary / maxMonetary);
            Decimal rfmValue = (recencyComponent + frequencyComponent + monetaryComponent) / 3;

            if (rfmValue >= 0.66) {
                score.segment = 'High';
            } else if (rfmValue >= 0.33) {
                score.segment = 'Mid';
            } else {
                score.segment = 'Low';
            }
        }

        return new List<RfmScore>(scoresByCustomer.values());
    }

    @TestVisible
    private static void updateProfiles(List<RfmScore> scores) {
        Set<String> customerIds = new Set<String>();
        Map<String, String> segmentByCustomerId = new Map<String, String>();
        for (RfmScore score : scores) {
            customerIds.add(score.customerId);
            segmentByCustomerId.put(score.customerId, score.segment);
        }

        List<CustomerProfile__c> profilesToUpdate = new List<CustomerProfile__c>();
        for (CustomerProfile__c profile : [
            SELECT Id, ExternalCustomerId__c, CustomerSegment__c
            FROM CustomerProfile__c
            WHERE ExternalCustomerId__c IN :customerIds
        ]) {
            String newSegment = segmentByCustomerId.get(profile.ExternalCustomerId__c);
            if (newSegment != null && newSegment != profile.CustomerSegment__c) {
                profile.CustomerSegment__c = newSegment;
                profilesToUpdate.add(profile);
            }
        }
        if (!profilesToUpdate.isEmpty()) {
            update profilesToUpdate;
        }
    }

    /**
     * Finds profiles most similar to a seed profile within the same segment,
     * ranked by closeness of churn risk and lifetime value.
     */
    public static List<CustomerProfile__c> findLookalikeCustomers(Id seedProfileId, Integer maxResults) {
        if (seedProfileId == null) {
            throw new CortexServiceException('A seed profile Id is required to find lookalike customers.');
        }
        Integer resultLimit = (maxResults == null || maxResults <= 0) ? 10 : maxResults;

        List<CustomerProfile__c> seedRecords = [
            SELECT Id, CustomerSegment__c, ChurnRiskScore__c, LifetimeValue__c
            FROM CustomerProfile__c
            WHERE Id = :seedProfileId
            LIMIT 1
        ];
        if (seedRecords.isEmpty()) {
            throw new CortexServiceException('Seed CustomerProfile__c record not found: ' + seedProfileId);
        }
        CustomerProfile__c seed = seedRecords[0];

        List<CustomerProfile__c> candidates = [
            SELECT Id, Name, CustomerName__c, CustomerSegment__c, ChurnRiskScore__c, LifetimeValue__c
            FROM CustomerProfile__c
            WHERE CustomerSegment__c = :seed.CustomerSegment__c AND Id != :seed.Id
            LIMIT 2000
        ];

        Decimal seedRisk = seed.ChurnRiskScore__c != null ? seed.ChurnRiskScore__c : 0;
        Decimal seedValue = seed.LifetimeValue__c != null ? seed.LifetimeValue__c : 0;

        List<ScoredCandidate> scored = new List<ScoredCandidate>();
        for (CustomerProfile__c candidate : candidates) {
            Decimal candidateRisk = candidate.ChurnRiskScore__c != null ? candidate.ChurnRiskScore__c : 0;
            Decimal candidateValue = candidate.LifetimeValue__c != null ? candidate.LifetimeValue__c : 0;
            Decimal riskDelta = candidateRisk - seedRisk;
            Decimal valueDelta = (candidateValue - seedValue) / 1000;
            Double distance = Math.sqrt(((riskDelta * riskDelta) + (valueDelta * valueDelta)).doubleValue());
            scored.add(new ScoredCandidate(candidate, distance));
        }
        scored.sort();

        List<CustomerProfile__c> results = new List<CustomerProfile__c>();
        for (Integer i = 0; i < scored.size() && i < resultLimit; i++) {
            results.add(scored[i].profile);
        }
        return results;
    }

    private class ScoredCandidate implements Comparable {
        CustomerProfile__c profile;
        Double distance;

        ScoredCandidate(CustomerProfile__c profile, Double distance) {
            this.profile = profile;
            this.distance = distance;
        }

        public Integer compareTo(Object other) {
            Double otherDistance = ((ScoredCandidate) other).distance;
            if (distance == otherDistance) {
                return 0;
            }
            return distance < otherDistance ? -1 : 1;
        }
    }

    /**
     * Safe dynamic segment query: fieldName and operatorSymbol are validated
     * against whitelists before being concatenated into the query string, and
     * the comparison value is always passed as a bind variable - never
     * concatenated - to prevent SOQL injection.
     */
    public static List<CustomerProfile__c> querySegment(String fieldName, String operatorSymbol, Object value, Integer maxResults) {
        if (!ALLOWED_FILTER_FIELDS.contains(fieldName)) {
            throw new CortexServiceException('Filtering on field "' + fieldName + '" is not permitted.');
        }
        if (!ALLOWED_OPERATORS.containsKey(operatorSymbol)) {
            throw new CortexServiceException('Operator "' + operatorSymbol + '" is not permitted.');
        }
        Integer resultLimit = (maxResults == null || maxResults <= 0 || maxResults > 2000) ? 200 : maxResults;

        String query = 'SELECT Id, Name, CustomerName__c, Email__c, CustomerSegment__c, ChurnRiskScore__c, LifetimeValue__c ' +
            'FROM CustomerProfile__c WHERE ' + fieldName + ' ' + ALLOWED_OPERATORS.get(operatorSymbol) + ' :value ' +
            'LIMIT :resultLimit';
        return Database.query(query);
    }
}
