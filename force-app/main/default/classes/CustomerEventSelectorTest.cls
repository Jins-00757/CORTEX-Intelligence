@IsTest
private class CustomerEventSelectorTest {

    @IsTest
    static void emptyOrNullCustomerSetReturnsNoEvents() {
        System.assertEquals(0, CustomerEventSelector.selectSince(null, System.now()).size());
        System.assertEquals(0, CustomerEventSelector.selectSince(new Set<String>(), System.now()).size());
    }

    @IsTest
    static void stubIsFilteredByCustomerAndWindow() {
        CortexTestUtils.stubEvents(new List<CustomerDataEvents__b>{
            CortexTestUtils.event('SEL-1', 'Login', 1, null),
            CortexTestUtils.event('SEL-1', 'Login', 30, null),
            CortexTestUtils.event('SEL-2', 'Login', 1, null)
        });

        Test.startTest();
        List<CustomerDataEvents__b> events = CustomerEventSelector.selectSince(
            new Set<String>{ 'SEL-1' }, System.now().addDays(-7)
        );
        Test.stopTest();

        System.assertEquals(1, events.size());
        System.assertEquals('SEL-1', events[0].CustomerId__c);
    }
}
