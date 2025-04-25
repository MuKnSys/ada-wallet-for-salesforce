public with sharing class CreateNewWalletCtrl {
    @AuraEnabled
    public static Id createWallet(String walletSetId, String walletName, String address, String accountPrivateKey, String accountPublicKey, Integer accountIndex) {
        try {
            Wallet__c newWallet = new Wallet__c(
                Wallet_Set__c = walletSetId,
                Name = walletName,
                Address__c = address,
                Account_Private_Key__c = accountPrivateKey,
                Account_Public_Key__c = accountPublicKey,
                Account_Index__c = accountIndex
            );
            insert newWallet;
            
            Logger.logInfo('Wallet created: ' + newWallet.Name + ' for Wallet Set: ' + walletSetId + ' with Account Index: ' + accountIndex + ' by User: ' + UserInfo.getName());

            return newWallet.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Wallet: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled(cacheable=true)
    public static Wallet__c getWalletById(String walletId) {
        try {
            if (String.isBlank(walletId)) {
                throw new AuraHandledException('Wallet ID is required');
            }
            Wallet__c wallet = WalletSelector.getWalletById(walletId);
            if (wallet == null) {
                throw new AuraHandledException('Wallet not found for ID: ' + walletId);
            }
            Logger.logInfo('Retrieved wallet for ID: ' + walletId + ' by User: ' + UserInfo.getName());
            return wallet;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled
    public static Integer getNextAccountIndex(String walletSetId) {
        try {
            List<Wallet__c> wallets = walletSelector.getWalletsByWalletSetId(walletSetId);
            
            // If no wallets exist, default to 0
            if (wallets.isEmpty()) {
                Logger.logInfo('No wallets found for Wallet Set: ' + walletSetId + ', defaulting to Account Index 0');
                return 0;
            }

            // Find the first unused index (gap or next after highest)
            Set<Integer> usedIndices = new Set<Integer>();
            for (Wallet__c wallet : wallets) {
                if (wallet.Account_Index__c != null) {
                    usedIndices.add(wallet.Account_Index__c.intValue());
                }
            }

            Integer nextIndex = 0;
            while (usedIndices.contains(nextIndex)) {
                nextIndex++;
            }

            Logger.logInfo('Next available Account Index for Wallet Set: ' + walletSetId + ' is ' + nextIndex);
            return nextIndex;
        } catch (Exception e) {
            Logger.logError('Error getting next account index for Wallet Set: ' + walletSetId + ': ' + e.getMessage());
            throw new AuraHandledException('Error getting next account index: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled
    public static String isIndexValid(String walletSetId, Integer accountIndex) {
        try {
            // Fetch Wallet_Set__c Name for error message
            Wallet_Set__c walletSet = WalletSetSelector.getWalletSetById(walletSetId);

            // Check if the index is already used
            List<Wallet__c> wallets = WalletSelector.getWalletByWalletSetAndAccountIndex(walletSetId, accountIndex);

            if (!wallets.isEmpty()) {
                String errorMessage = 'Account ' + accountIndex + ' already exists for Wallet Set ' + walletSet.Name + '. Try a different wallet set or Account Index.';
                Logger.logInfo('Validation failed for Wallet Set: ' + walletSetId + ', Account Index: ' + accountIndex + ': ' + errorMessage);
                return errorMessage;
            }

            Logger.logInfo('Account Index ' + accountIndex + ' is valid for Wallet Set: ' + walletSetId);
            return null;
        } catch (Exception e) {
            Logger.logError('Error validating account index for Wallet Set: ' + walletSetId + ', Account Index: ' + accountIndex + ': ' + e.getMessage());
            throw new AuraHandledException('Error validating account index: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled(cacheable=true)
    public static Boolean checkIsAddressUsed(String address) {
        try {            
            return BlockfrostService.isAddressUsed(address);
        } catch (Exception e) {            
            throw new AuraHandledException('Failed to check if address is used: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static Wallet_Set__c getWalletSetWithSeedPhrase(Id walletSetId) {
        try {            
            return WalletSetSelector.getWalletSetWithSeedPhrase(walletSetId);
        } catch (Exception e) {            
            throw new AuraHandledException('Failed to check is address used: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getDecryptedSeedPhrase(Id walletSetId) {
        try {            
            return EncryptedDataService.getDecryptedSeedPhrase(walletSetId);
        } catch (Exception e) {            
            throw new AuraHandledException('Failed to get seed phrase: ' + e.getMessage());
        }
    }
}