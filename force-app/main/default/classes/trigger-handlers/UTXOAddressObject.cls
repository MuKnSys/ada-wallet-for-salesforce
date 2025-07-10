public with sharing class UTXOAddressObject extends TriggerHandlerADA{
    public override void afterInsert(List<SObject> records) {        
        syncAssetsAndTransactions(records);
    }

    private void syncAssetsAndTransactions(List<SObject> records) {
        Set<Id> utxoAddressIds = new Set<Id>();
        for (SObject record : records) {
            utxoAddressIds.add(record.Id);
        }
        
        if (!utxoAddressIds.isEmpty()) {
            System.enqueueJob(new UTXOAssetSyncQueueable(new List<Id>(utxoAddressIds)));
        }
    }
}