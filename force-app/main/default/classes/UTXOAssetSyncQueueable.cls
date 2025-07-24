public class UTXOAssetSyncQueueable implements Queueable, Database.AllowsCallouts {
    private List<Id> utxoAddressIds;
    
    public UTXOAssetSyncQueueable(List<Id> utxoAddressIds) {
        this.utxoAddressIds = utxoAddressIds;
    }
    
    public void execute(QueueableContext context) {
        Set<Id> processedWalletIds = new Set<Id>();
        List<UTXO_Address__c> addressesToUpdate = new List<UTXO_Address__c>();
        
        List<UTXO_Address__c> utxoAddressesList = UTXOAddressSelector.getAddressesByIds(utxoAddressIds);
        Map<Id, UTXO_Address__c> utxoAddresses = new Map<Id, UTXO_Address__c>(utxoAddressesList);
        
        for (Id utxoAddressId : utxoAddressIds) {
            Map<String, Object> result = UTXOHelper.syncAssetsAndTransactions(utxoAddressId);
            
            UTXO_Address__c utxoAddress = utxoAddresses.get(utxoAddressId);
            if (utxoAddress != null && utxoAddress.Wallet__c != null) {
                processedWalletIds.add(utxoAddress.Wallet__c);
                
                // Check if address is actually used based on sync statistics
                if (result != null && result.containsKey('statistics')) {
                    Map<String, Object> stats = (Map<String, Object>) result.get('statistics');
                    Boolean isActuallyUsed = isAddressActuallyUsed(stats);
                    
                    // Update Is_Used__c field if it has changed
                    if (utxoAddress.Is_Used__c != isActuallyUsed) {
                        utxoAddress.Is_Used__c = isActuallyUsed;
                        addressesToUpdate.add(utxoAddress);
                    }
                }
            }
        }
        
        // Update addresses with new Is_Used__c values
        if (!addressesToUpdate.isEmpty()) {
            update addressesToUpdate;
        }
        
        // Publish wallet sync event for each unique wallet after all syncs are complete
        for (Id walletId : processedWalletIds) {
            BlockfrostService.publishWalletSyncEvent(walletId, 'assetsUpdated');
        }
    }
    
    private Boolean isAddressActuallyUsed(Map<String, Object> stats) {
        Integer assetsInserted = (Integer) (stats.get('assetsInserted') != null ? stats.get('assetsInserted') : 0);
        Integer assetsUpdated = (Integer) (stats.get('assetsUpdated') != null ? stats.get('assetsUpdated') : 0);
        Integer transactionsInserted = (Integer) (stats.get('transactionsInserted') != null ? stats.get('transactionsInserted') : 0);
        Integer transactionsUpdated = (Integer) (stats.get('transactionsUpdated') != null ? stats.get('transactionsUpdated') : 0);
        
        return assetsInserted > 0 || assetsUpdated > 0 || transactionsInserted > 0 || transactionsUpdated > 0;
    }
} 