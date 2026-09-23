@IsTest
private class CustomerProfileTriggerHandlerTest {

    @IsTest
    static void testDefaultsAppliedOnInsert() {
        CustomerProfile__c profile = new CustomerProfile__c(
            ExternalCustomerId__c = 'EXT-001',
            Email__c = '  Test@Example.COM  '
        );

        Test.startTest();
        insert profile;
        Test.stopTest();

        CustomerProfile__c inserted = [
            SELECT Email__c, ChurnRiskScore__c, CustomerSegment__c
            FROM CustomerProfile__c
            WHERE Id = :profile.Id
        ];

        System.assertEquals('test@example.com', inserted.Email__c, 'Email should be trimmed and lowercased');
        System.assertEquals(0, inserted.ChurnRiskScore__c, 'Churn risk score should default to 0');
        System.assertEquals('Unclassified', inserted.CustomerSegment__c, 'Segment should default to Unclassified');
    }

    @IsTest
    static void testExplicitValuesPreservedOnInsert() {
        CustomerProfile__c profile = new CustomerProfile__c(
            ExternalCustomerId__c = 'EXT-002',
            ChurnRiskScore__c = 0.75,
            CustomerSegment__c = 'High'
        );

        Test.startTest();
        insert profile;
        Test.stopTest();

        CustomerProfile__c inserted = [
            SELECT ChurnRiskScore__c, CustomerSegment__c
            FROM CustomerProfile__c
            WHERE Id = :profile.Id
        ];

        System.assertEquals(0.75, inserted.ChurnRiskScore__c, 'Explicit churn risk score should be preserved');
        System.assertEquals('High', inserted.CustomerSegment__c, 'Explicit segment should be preserved');
    }

    @IsTest
    static void testDefaultsAppliedOnUpdate() {
        CustomerProfile__c profile = new CustomerProfile__c(
            ExternalCustomerId__c = 'EXT-003',
            ChurnRiskScore__c = 0.5,
            CustomerSegment__c = 'Mid'
        );
        insert profile;

        profile.ChurnRiskScore__c = null;
        profile.CustomerSegment__c = null;

        Test.startTest();
        update profile;
        Test.stopTest();

        CustomerProfile__c updated = [
            SELECT ChurnRiskScore__c, CustomerSegment__c
            FROM CustomerProfile__c
            WHERE Id = :profile.Id
        ];

        System.assertEquals(0, updated.ChurnRiskScore__c, 'Churn risk score should reset to default on update');
        System.assertEquals('Unclassified', updated.CustomerSegment__c, 'Segment should reset to default on update');
    }

    @IsTest
    static void testChurnRiskScoreOutOfRangeIsRejected() {
        CustomerProfile__c profile = new CustomerProfile__c(
            ExternalCustomerId__c = 'EXT-004',
            ChurnRiskScore__c = 1.5
        );

        Test.startTest();
        try {
            insert profile;
            System.assert(false, 'Expected a validation exception for an out-of-range churn risk score');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Churn Risk Score must be between 0 and 1'),
                'Expected the range validation error message'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void testNegativeLifetimeValueIsRejected() {
        CustomerProfile__c profile = new CustomerProfile__c(
            ExternalCustomerId__c = 'EXT-005',
            LifetimeValue__c = -10
        );

        Test.startTest();
        try {
            insert profile;
            System.assert(false, 'Expected a validation exception for a negative lifetime value');
        } catch (DmlException e) {
            System.assert(
                e.getMessage().contains('Lifetime Value cannot be negative'),
                'Expected the non-negative validation error message'
            );
        }
        Test.stopTest();
    }
}
