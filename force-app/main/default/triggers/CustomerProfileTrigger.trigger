trigger CustomerProfileTrigger on CustomerProfile__c (before insert, before update) {
    if (Trigger.isBefore) {
        if (Trigger.isInsert) {
            CustomerProfileTriggerHandler.beforeInsert(Trigger.new);
        } else if (Trigger.isUpdate) {
            CustomerProfileTriggerHandler.beforeUpdate(Trigger.new);
        }
    }
}
