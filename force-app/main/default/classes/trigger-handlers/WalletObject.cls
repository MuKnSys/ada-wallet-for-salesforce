public with sharing class WalletObject extends TriggerHandlerADA {
    public override void beforeInsert(List<SObject> records) {        
        validateWalletSetIndexUniqueness((List<Wallet__c>) records, null);
    }
    
    public override void beforeUpdate(List<SObject> records) {        
        validateWalletSetIndexUniqueness((List<Wallet__c>) records, (Map<Id, Wallet__c>) Trigger.oldMap);
    }

    private void validateWalletSetIndexUniqueness(List<Wallet__c> wallets, Map<Id, Wallet__c> oldMap) {
        // Map to store Wallet_Set__c to Set of Account_Index__c for quick lookup
        Map<Id, Set<Integer>> walletSetToIndices = new Map<Id, Set<Integer>>();

        // Step 1: Collect existing Wallet_Set__c and Account_Index__c combinations (excluding records being updated)
        Set<Id> walletIds = new Set<Id>();
        for (Wallet__c wallet : wallets) {
            if (wallet.Id != null) {
                walletIds.add(wallet.Id);
            }
        }
        List<Wallet__c> existingWallets = WalletSelector.getWalletsExcludingIds(walletIds);

        for (Wallet__c wallet : existingWallets) {
            if (!walletSetToIndices.containsKey(wallet.Wallet_Set__c)) {
                walletSetToIndices.put(wallet.Wallet_Set__c, new Set<Integer>());
            }
            walletSetToIndices.get(wallet.Wallet_Set__c).add((Integer) wallet.Account_Index__c);
        }

        // Step 2: Validate new and updated records
        for (Wallet__c wallet : wallets) {
            // Skip validation if Wallet_Set__c or Account_Index__c is null
            if (wallet.Wallet_Set__c == null || wallet.Account_Index__c == null) {
                continue;
            }

            // For updates, check if Wallet_Set__c or Account_Index__c has changed
            if (oldMap != null) {
                Wallet__c oldWallet = oldMap.get(wallet.Id);
                if (oldWallet.Wallet_Set__c == wallet.Wallet_Set__c && oldWallet.Account_Index__c == wallet.Account_Index__c) {
                    continue; // No change in relevant fields, skip validation
                }
            }

            // Check if the Account_Index__c already exists for this Wallet_Set__c
            if (walletSetToIndices.containsKey(wallet.Wallet_Set__c) && 
                walletSetToIndices.get(wallet.Wallet_Set__c).contains((Integer) wallet.Account_Index__c)) {
                wallet.addError('A Wallet with Wallet_Set__c ' + wallet.Wallet_Set__c + 
                            ' and Account_Index__c ' + wallet.Account_Index__c + 
                            ' already exists. Please choose a different Account Index.');
            }

            // Add the current record's Account_Index__c to the map to prevent duplicates within the same transaction
            if (!walletSetToIndices.containsKey(wallet.Wallet_Set__c)) {
                walletSetToIndices.put(wallet.Wallet_Set__c, new Set<Integer>());
            }
            walletSetToIndices.get(wallet.Wallet_Set__c).add((Integer) wallet.Account_Index__c);
        }
    }
}