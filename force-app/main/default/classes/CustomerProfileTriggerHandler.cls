/**
 * Before-insert/before-update handler for CustomerProfile__c.
 * Normalizes email formatting and applies safe defaults for scoring/segmentation
 * fields so downstream reporting and validation rules never see null risk data.
 */
public with sharing class CustomerProfileTriggerHandler {

    private static final String DEFAULT_SEGMENT = 'Unclassified';

    public static void beforeInsert(List<CustomerProfile__c> newProfiles) {
        applyDefaults(newProfiles);
    }

    public static void beforeUpdate(List<CustomerProfile__c> updatedProfiles) {
        applyDefaults(updatedProfiles);
    }

    private static void applyDefaults(List<CustomerProfile__c> profiles) {
        for (CustomerProfile__c profile : profiles) {
            if (String.isNotBlank(profile.Email__c)) {
                profile.Email__c = profile.Email__c.trim().toLowerCase();
            }
            if (profile.ChurnRiskScore__c == null) {
                profile.ChurnRiskScore__c = 0;
            }
            if (String.isBlank(profile.CustomerSegment__c)) {
                profile.CustomerSegment__c = DEFAULT_SEGMENT;
            }
        }
    }
}
