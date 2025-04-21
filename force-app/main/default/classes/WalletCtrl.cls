public with sharing class WalletCtrl {
    @AuraEnabled
    public static Id createWallet(String walletSetId, String walletName, String address, String accountPrivateKey, String accountPublicKey, Integer accountIndex) {
        try {
            // Validate input
            if (String.isBlank(walletSetId)) {
                throw new AuraHandledException('Wallet Set ID is required');
            }
            if (String.isBlank(walletName)) {
                throw new AuraHandledException('Wallet Name is required');
            }
            if (String.isBlank(address)) {
                throw new AuraHandledException('Wallet Address is required');
            }
            if (String.isBlank(accountPrivateKey)) {
                throw new AuraHandledException('Account Private Key is required');
            }
            if (String.isBlank(accountPublicKey)) {
                throw new AuraHandledException('Account Public Key is required');
            }
            if (accountIndex == null || accountIndex < 0) {
                throw new AuraHandledException('Account Index must be a non-negative integer');
            }

            // Create new Wallet__c record
            Wallet__c newWallet = new Wallet__c();
            newWallet.Wallet_Set__c = walletSetId;
            newWallet.Name = walletName;
            newWallet.Address__c = address;
            newWallet.Account_Private_Key__c = DataEncryptor.encrypt(accountPrivateKey);
            newWallet.Account_Public_Key__c = DataEncryptor.encrypt(accountPublicKey);
            newWallet.Account_Index__c = accountIndex;

            // Insert the record
            insert newWallet;

            // Log for debugging
            Logger.logInfo('Wallet created: ' + newWallet.Name + ' for Wallet Set: ' + walletSetId + ' with Account Index: ' + accountIndex + ' by User: ' + UserInfo.getName());

            return newWallet.Id;
        } catch (Exception e) {
            throw new AuraHandledException('Error creating Wallet: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled
    public static String decryptSeedPhrase(String encryptedSeedPhrase) {
        try {
            // Validate input
            if (String.isBlank(encryptedSeedPhrase)) {
                throw new AuraHandledException('Encrypted Seed Phrase is required');
            }

            // Decrypt using DataEncryptor
            String decryptedSeedPhrase = DataEncryptor.decrypt(encryptedSeedPhrase);

            // Log for debugging
            Logger.logInfo('Seed Phrase decrypted for Wallet Set by ' + UserInfo.getName() + ' (Id: ' + UserInfo.getUserId() + ')');

            return decryptedSeedPhrase;
        } catch (Exception e) {
            throw new AuraHandledException('Error decrypting Seed Phrase: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled
    public static String getDecryptedWalletSetSeedPhrase(Id walletSetId) {
        try {
            if (String.isBlank(walletSetId)) {
                throw new AuraHandledException('Wallet Set ID is required');
            }
            Wallet_Set__c walletSet = WalletSetSelector.getWalletSetById(walletSetId);
            if (walletSet.Seed_Phrase__c == null) {
                throw new AuraHandledException('Seed Phrase is missing for the Wallet Set');
            }
            if (!hasAccessToDecrypt()) {
                throw new AuraHandledException('Access denied to decrypt seed phrase');
            }
            String decryptedSeedPhrase = DataEncryptor.decrypt(walletSet.Seed_Phrase__c);
            Logger.logInfo('Seed Phrase decrypted for Wallet Set: ' + walletSetId + ' by User: ' + UserInfo.getName());
            return decryptedSeedPhrase;
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving and decrypting seed phrase: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled
    public static Wallet__c getWalletById(String walletId) {
        try {
            if (String.isBlank(walletId)) {
                throw new AuraHandledException('Wallet ID is required');
            }
            List<Wallet__c> wallets = [
                SELECT Id, Wallet_Set__c, Account_Index__c
                FROM Wallet__c
                WHERE Id = :walletId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];
            if (wallets.isEmpty()) {
                throw new AuraHandledException('Wallet not found for ID: ' + walletId);
            }
            Logger.logInfo('Retrieved wallet for ID: ' + walletId + ' by User: ' + UserInfo.getName());
            return wallets[0];
        } catch (Exception e) {
            throw new AuraHandledException('Error retrieving wallet: ' + e.getMessage());
        } finally {
            Logger.commitLogs();
        }
    }

    @AuraEnabled
    public static Integer getNextAccountIndex(String walletSetId) {
        try {
            // Validate input
            if (String.isBlank(walletSetId)) {
                throw new AuraHandledException('Wallet Set ID is required');
            }

            // Query all Wallet__c records for the Wallet_Set__c to get used indices
            List<Wallet__c> wallets = [
                SELECT Account_Index__c
                FROM Wallet__c
                WHERE Wallet_Set__c = :walletSetId
                AND Account_Index__c != NULL
                WITH SECURITY_ENFORCED
                ORDER BY Account_Index__c ASC
            ];

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
            // Validate input
            if (String.isBlank(walletSetId)) {
                throw new AuraHandledException('Wallet Set ID is required');
            }
            if (accountIndex == null || accountIndex < 0) {
                throw new AuraHandledException('Account Index must be a non-negative integer');
            }

            // Fetch Wallet_Set__c Name for error message
            Wallet_Set__c walletSet = [
                SELECT Name
                FROM Wallet_Set__c
                WHERE Id = :walletSetId
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

            // Check if the index is already used
            List<Wallet__c> wallets = [
                SELECT Id
                FROM Wallet__c
                WHERE Wallet_Set__c = :walletSetId
                AND Account_Index__c = :accountIndex
                WITH SECURITY_ENFORCED
                LIMIT 1
            ];

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

    private static Boolean hasAccessToDecrypt() {        
        Set<Id> psIds = new Set<Id>();
        for (PermissionSetAssignment psa : [SELECT PermissionSetId FROM PermissionSetAssignment WHERE AssigneeId = :UserInfo.getUserId()]) {
            psIds.add(psa.PermissionSetId);
        }
        List<PermissionSet> permissionSets = [SELECT Id FROM PermissionSet WHERE Name = 'EncryptedDataAccess' LIMIT 1];
        return !permissionSets.isEmpty() && psIds.contains(permissionSets[0].Id);
    }
}