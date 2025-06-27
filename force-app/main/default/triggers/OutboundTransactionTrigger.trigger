trigger OutboundTransactionTrigger on Outbound_Transaction__c (before update) {
    OutboundTransactionTriggerHandler.handleBeforeUpdate(Trigger.new, Trigger.oldMap);
} 