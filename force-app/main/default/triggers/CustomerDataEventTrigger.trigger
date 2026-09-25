trigger CustomerDataEventTrigger on CustomerDataEvent__e (after insert) {
    CustomerDataEventTriggerHandler.afterInsert(Trigger.new);
}
