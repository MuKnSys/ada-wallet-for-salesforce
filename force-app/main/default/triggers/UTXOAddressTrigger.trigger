trigger UTXOAddressTrigger on UTXO_Address__c (after insert) {
    if (TriggerSettingsADA.utxoAddressTrigger) {
        new UTXOAddressObject().onTrigger();
    }
} 