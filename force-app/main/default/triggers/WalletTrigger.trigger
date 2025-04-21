trigger WalletTrigger on Wallet__c (before insert, before update) {
    // Map to store Wallet_Set__c to Set of Account_Index__c for quick lookup
    Map<Id, Set<Integer>> walletSetToIndices = new Map<Id, Set<Integer>>();

    // Step 1: Collect existing Wallet_Set__c and Account_Index__c combinations (excluding records being updated)
    List<Wallet__c> existingWallets = [
        SELECT Wallet_Set__c, Account_Index__c
        FROM Wallet__c
        WHERE Wallet_Set__c != null AND Account_Index__c != null
        AND Id NOT IN :Trigger.newMap?.keySet()
        WITH SECURITY_ENFORCED
    ];

    for (Wallet__c wallet : existingWallets) {
        if (!walletSetToIndices.containsKey(wallet.Wallet_Set__c)) {
            walletSetToIndices.put(wallet.Wallet_Set__c, new Set<Integer>());
        }
        walletSetToIndices.get(wallet.Wallet_Set__c).add((Integer)wallet.Account_Index__c);
    }

    // Step 2: Validate new and updated records
    for (Wallet__c wallet : Trigger.new) {
        // Skip validation if Wallet_Set__c or Account_Index__c is null
        if (wallet.Wallet_Set__c == null || wallet.Account_Index__c == null) {
            continue;
        }

        // For updates, check if Wallet_Set__c or Account_Index__c has changed
        if (Trigger.isUpdate) {
            Wallet__c oldWallet = Trigger.oldMap.get(wallet.Id);
            if (oldWallet.Wallet_Set__c == wallet.Wallet_Set__c && oldWallet.Account_Index__c == wallet.Account_Index__c) {
                continue; // No change in relevant fields, skip validation
            }
        }

        // Check if the Account_Index__c already exists for this Wallet_Set__c
        if (walletSetToIndices.containsKey(wallet.Wallet_Set__c) && 
            walletSetToIndices.get(wallet.Wallet_Set__c).contains((Integer)wallet.Account_Index__c)) {
            wallet.addError('A Wallet with Wallet_Set__c ' + wallet.Wallet_Set__c + 
                           ' and Account_Index__c ' + wallet.Account_Index__c + 
                           ' already exists. Please choose a different Account Index.');
        }

        // Add the current record's Account_Index__c to the map to prevent duplicates within the same transaction
        if (!walletSetToIndices.containsKey(wallet.Wallet_Set__c)) {
            walletSetToIndices.put(wallet.Wallet_Set__c, new Set<Integer>());
        }
        walletSetToIndices.get(wallet.Wallet_Set__c).add((Integer)wallet.Account_Index__c);
    }
}