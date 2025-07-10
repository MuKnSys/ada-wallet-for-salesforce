public class UTXOAssetSyncQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> utxoAddressIds;
    
    public UTXOAssetSyncQueueable(List<Id> utxoAddressIds) {
        this.utxoAddressIds = utxoAddressIds;
    }
    
    public void execute(QueueableContext context) {
        Set<Id> processedWalletIds = new Set<Id>();
        
        for (Id utxoAddressId : utxoAddressIds) {
            Map<String, Object> result = UTXOAssetController.syncAssetsAndTransactions(utxoAddressId);            
            
            UTXO_Address__c utxoAddress = [SELECT Wallet__c FROM UTXO_Address__c WHERE Id = :utxoAddressId LIMIT 1];
            processedWalletIds.add(utxoAddress.Wallet__c);
        }
        
        // Publish wallet sync event for each unique wallet after all syncs are complete
        for (Id walletId : processedWalletIds) {
            BlockfrostService.publishWalletSyncEvent(walletId, 'assetsUpdated');
        }
    }
} 