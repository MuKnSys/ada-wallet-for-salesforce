trigger OutboundTransactionTrigger on Outbound_Transaction__c (after update) {
    if (TriggerSettingsADA.outboundTransactionTrigger) {
        new OutboundTransactionObject().onTrigger();
    }    
} 