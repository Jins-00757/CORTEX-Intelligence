/**
 * Shared fixtures for Cortex Apex tests.
 */
@IsTest
public class CortexTestUtils {

    /**
     * Replaces the cached CortexConfig__mdt with an in-memory record, so tests
     * can exercise feature-flag branches without deploying metadata.
     */
    public static void useConfig(Boolean predictionsEnabled, Decimal churnRiskThreshold) {
        CortexConfigService.cachedConfig = new CortexConfig__mdt(
            DeveloperName = 'Test_Config',
            ApiRateLimitPerHour__c = 1000,
            BatchSize__c = 200,
            CacheTTLMinutes__c = 60,
            ChurnRiskThreshold__c = churnRiskThreshold,
            DataRetentionDays__c = 730,
            EnableAuditLogging__c = true,
            EnablePredictions__c = predictionsEnabled
        );
    }

    public static void disablePredictions() {
        useConfig(false, 0.7);
    }

    /**
     * Routes every CustomerDataEvents__b read through an in-memory list
     * (Big Object SOQL is not usable inside the Apex test runner).
     */
    public static void stubEvents(List<CustomerDataEvents__b> events) {
        CustomerEventSelector.stubbedEvents = events == null ? new List<CustomerDataEvents__b>() : events;
    }

    public static CustomerDataEvents__b event(String customerId, String eventType, Integer daysAgo, Decimal amount) {
        return new CustomerDataEvents__b(
            CustomerId__c = customerId,
            EventId__c = customerId + '-' + eventType + '-' + daysAgo,
            EventType__c = eventType,
            EventTimestamp__c = System.now().addDays(-daysAgo),
            Amount__c = amount
        );
    }

    /**
     * Customer activity that scores 0 composite churn risk: 4 recent
     * purchases at the 100 target order value plus 10 engagement events.
     */
    public static List<CustomerDataEvents__b> healthyHistory(String customerId) {
        List<CustomerDataEvents__b> events = new List<CustomerDataEvents__b>();
        for (Integer i = 0; i < 4; i++) {
            events.add(event(customerId, 'Purchase', i, 100));
        }
        for (Integer i = 0; i < 10; i++) {
            events.add(event(customerId, 'Login', i, null));
        }
        return events;
    }

    /**
     * A Standard User, optionally granted the Cortex_API_Integration
     * permission set - i.e. a realistic integration caller whose object and
     * field-level security is what the REST API must enforce.
     */
    public static User createApiUser(Boolean withApiPermissionSet) {
        String uniqueKey = UserInfo.getOrganizationId() + String.valueOf(Crypto.getRandomInteger()).remove('-');
        User apiUser = new User(
            ProfileId = [SELECT Id FROM Profile WHERE Name = 'Standard User' LIMIT 1].Id,
            Username = 'cortex.api.' + uniqueKey + '@example.com',
            Email = 'cortex.api@example.com',
            LastName = 'Cortex API',
            Alias = 'cxapi',
            TimeZoneSidKey = 'Europe/London',
            LocaleSidKey = 'en_GB',
            EmailEncodingKey = 'UTF-8',
            LanguageLocaleKey = 'en_US'
        );
        insert apiUser;
        if (withApiPermissionSet) {
            insert new PermissionSetAssignment(
                AssigneeId = apiUser.Id,
                PermissionSetId = [SELECT Id FROM PermissionSet WHERE Name = 'Cortex_API_Integration' LIMIT 1].Id
            );
        }
        return apiUser;
    }

    public static List<CustomerProfile__c> insertProfiles(List<String> externalIds) {
        List<CustomerProfile__c> profiles = new List<CustomerProfile__c>();
        for (String externalId : externalIds) {
            profiles.add(new CustomerProfile__c(ExternalCustomerId__c = externalId, CustomerName__c = 'Test ' + externalId));
        }
        insert profiles;
        return profiles;
    }

    public static Map<String, CustomerProfile__c> profilesByExternalId() {
        Map<String, CustomerProfile__c> result = new Map<String, CustomerProfile__c>();
        for (CustomerProfile__c profile : [
            SELECT Id, ExternalCustomerId__c, ChurnRiskScore__c, CustomerSegment__c
            FROM CustomerProfile__c
        ]) {
            result.put(profile.ExternalCustomerId__c, profile);
        }
        return result;
    }
}
